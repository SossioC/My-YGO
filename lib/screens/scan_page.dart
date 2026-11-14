import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../models/card_info.dart';
import '../services/code_parser.dart';
import '../services/debug_log.dart';
import '../services/sounds.dart';
import '../services/ygo_api.dart';
import '../theme.dart';

enum _Frame { idle, ok, error }

enum _Banner { hint, searching, success, error, duplicate }

class ScanEntry {
  final CardInfo card;
  String code;
  int qtyIt = 0;
  int qtyEn = 0;
  String lastLang = 'en';

  ScanEntry(this.card, this.code);

  int qty(String lang) => lang == 'it' ? qtyIt : qtyEn;

  void add(String lang) {
    if (lang == 'it') {
      qtyIt++;
    } else {
      qtyEn++;
    }
    lastLang = lang;
  }

  void undo() {
    if (lastLang == 'it' && qtyIt > 0) {
      qtyIt--;
    } else if (qtyEn > 0) {
      qtyEn--;
    } else if (qtyIt > 0) {
      qtyIt--;
    }
  }

  bool get isEmpty => qtyIt == 0 && qtyEn == 0;
}

class ScanPage extends StatefulWidget {
  final bool active;

  const ScanPage({super.key, required this.active});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> with WidgetsBindingObserver {
  final TextRecognizer _recognizer =
      TextRecognizer(script: TextRecognitionScript.latin);
  final YgoApi _api = YgoApi();
  final Sounds _sounds = Sounds();
  final List<ScanEntry> _entries = [];

  CameraController? _controller;
  CameraDescription? _camera;
  bool _starting = false;
  String? _cameraError;

  bool _processing = false;
  int _lastFrameMs = 0;
  bool _formatLogged = false;

  String? _lockedCode;
  String? _candidate;
  int _candidateHits = 0;
  int _lastCodeSeenMs = 0;
  int? _noTextSince;
  int? _unreadableSince;
  int _lastErrorMs = 0;
  String _lastOcr = '';

  _Frame _frame = _Frame.idle;
  Timer? _frameTimer;

  _Banner _banner = _Banner.hint;
  String _bannerTitle = '';
  String _bannerMsg = '';
  CardInfo? _bannerCard;
  String? _bannerLang;
  String? _bannerCode;

  CardInfo? _pendingCard;
  String? _pendingLang;
  String? _pendingCode;

  static const Map<DeviceOrientation, int> _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.active) _startCamera();
  }

  @override
  void didUpdateWidget(covariant ScanPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active) {
      if (widget.active) {
        _startCamera();
      } else {
        _stopCamera();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (widget.active) _startCamera();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _stopCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _frameTimer?.cancel();
    _stopCamera(update: false);
    _recognizer.close();
    _sounds.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- camera

  Future<void> _startCamera() async {
    if (_starting || _controller != null) return;
    _starting = true;
    if (mounted) setState(() => _cameraError = null);
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        _cameraError = 'Nessuna fotocamera trovata.';
        return;
      }
      final cam = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );
      final ctrl = CameraController(
        cam,
        ResolutionPreset.veryHigh,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );
      await ctrl.initialize();
      try {
        await ctrl.setFocusMode(FocusMode.auto);
      } catch (_) {}
      if (!mounted || !widget.active) {
        await ctrl.dispose();
        return;
      }
      _camera = cam;
      _controller = ctrl;
      await ctrl.startImageStream(_onFrame);
      DebugLog.add('Fotocamera avviata (${cam.sensorOrientation} gradi)');
    } on CameraException catch (e) {
      DebugLog.add('Fotocamera: ${e.code} ${e.description}');
      _cameraError =
          'Fotocamera non disponibile (${e.code}). Controlla il permesso nelle impostazioni di Android.';
      _controller = null;
    } catch (e) {
      DebugLog.add('Fotocamera: $e');
      _cameraError = 'Errore della fotocamera: $e';
      _controller = null;
    } finally {
      _starting = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _stopCamera({bool update = true}) async {
    final c = _controller;
    _controller = null;
    _camera = null;
    if (update && mounted) setState(() {});
    if (c != null) {
      try {
        if (c.value.isStreamingImages) await c.stopImageStream();
      } catch (_) {}
      try {
        await c.dispose();
      } catch (_) {}
    }
  }

  InputImage? _toInputImage(CameraImage image) {
    final cam = _camera;
    final ctrl = _controller;
    if (cam == null || ctrl == null) return null;

    final comp = _orientations[ctrl.value.deviceOrientation];
    if (comp == null) return null;
    final rotDeg = (cam.sensorOrientation - comp + 360) % 360;
    final rotation = InputImageRotationValue.fromRawValue(rotDeg);
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format != InputImageFormat.nv21 || image.planes.length != 1) {
      if (!_formatLogged) {
        _formatLogged = true;
        DebugLog.add(
            'Formato immagine non supportato: raw=${image.format.raw} piani=${image.planes.length}');
      }
      return null;
    }
    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  // -------------------------------------------------------------- scanning

  Future<void> _onFrame(CameraImage image) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_processing || now - _lastFrameMs < 350) return;
    _processing = true;
    _lastFrameMs = now;
    try {
      final input = _toInputImage(image);
      if (input == null) return;
      final text = await _recognizer.processImage(input);
      if (!mounted) return;
      await _handleText(text.text);
    } catch (e) {
      DebugLog.add('Errore frame: $e');
    } finally {
      _processing = false;
    }
  }

  Future<void> _handleText(String raw) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    _lastOcr = raw.replaceAll('\n', ' | ');
    final codes = CodeParser.findAll(raw);
    final hasText = raw.trim().length >= 12;

    if (codes.isEmpty) {
      if (!hasText) {
        _noTextSince ??= now;
      } else {
        _noTextSince = null;
      }

      if (_lockedCode != null) {
        final gone = _noTextSince != null && now - _noTextSince! > 1000;
        final stale = now - _lastCodeSeenMs > 4000;
        if (gone || stale) {
          _lockedCode = null;
          _candidate = null;
          _candidateHits = 0;
        }
        return;
      }

      if (hasText) {
        _unreadableSince ??= now;
        if (now - _unreadableSince! > 2500 && now - _lastErrorMs > 4000) {
          _lastErrorMs = now;
          _fail('Codice non letto', 'Avvicina la carta o aggiungila a mano.',
              manual: true);
        }
      } else {
        _unreadableSince = null;
      }
      return;
    }

    _unreadableSince = null;
    _noTextSince = null;
    final code = codes.first;
    _lastCodeSeenMs = now;

    if (code.raw == _lockedCode) return;

    if (_candidate == code.raw) {
      _candidateHits++;
    } else {
      _candidate = code.raw;
      _candidateHits = 1;
    }
    if (_candidateHits < 2) return;

    _candidate = null;
    _candidateHits = 0;
    _lockedCode = code.raw;
    await _resolve(code);
  }

  Future<void> _resolve(ParsedCode code) async {
    final lang = code.lang;
    if (lang == null) {
      _fail('Lingua non gestita', 'Il codice ${code.raw} non è IT o EN.');
      return;
    }

    setState(() {
      _banner = _Banner.searching;
      _bannerMsg = 'Cerco ${code.raw}…';
    });

    final res = await _api.lookup(code);
    if (!mounted) return;

    if (res.networkError) {
      _fail('Errore di rete', 'Controlla la connessione e riprova.');
      return;
    }
    final card = res.card;
    if (card == null) {
      _fail('Carta non trovata', 'Codice letto: ${code.raw}', manual: true);
      return;
    }

    final existing = _entries.where((e) => e.card.id == card.id).toList();
    if (existing.isNotEmpty && existing.first.qty(lang) > 0) {
      _sounds.playOk();
      setState(() {
        _pendingCard = card;
        _pendingLang = lang;
        _pendingCode = code.raw;
        _banner = _Banner.duplicate;
        _bannerCard = card;
        _bannerLang = lang;
        _bannerCode = code.raw;
      });
      _flash(_Frame.ok);
      return;
    }

    _addCopy(card, lang, code.raw);
  }

  void _addCopy(CardInfo card, String lang, String code) {
    final idx = _entries.indexWhere((e) => e.card.id == card.id);
    ScanEntry entry;
    if (idx >= 0) {
      entry = _entries.removeAt(idx);
    } else {
      entry = ScanEntry(card, code);
    }
    entry.add(lang);
    entry.code = code;
    _sounds.playOk();
    setState(() {
      _entries.insert(0, entry);
      _pendingCard = null;
      _banner = _Banner.success;
      _bannerCard = card;
      _bannerLang = lang;
      _bannerCode = code;
    });
    _flash(_Frame.ok);
  }

  void _answerDuplicate(bool yes) {
    final card = _pendingCard;
    final lang = _pendingLang;
    final code = _pendingCode;
    if (yes && card != null && lang != null && code != null) {
      _addCopy(card, lang, code);
    } else {
      setState(() {
        _pendingCard = null;
        _banner = _Banner.hint;
      });
    }
  }

  void _fail(String title, String msg, {bool manual = false}) {
    _sounds.playError();
    if (!mounted) return;
    setState(() {
      _banner = _Banner.error;
      _bannerTitle = title;
      _bannerMsg = msg;
      _pendingCard = null;
    });
    _flash(_Frame.error);
    DebugLog.add('ERRORE: $title - $msg');
  }

  void _flash(_Frame f, {int ms = 1200}) {
    _frameTimer?.cancel();
    if (!mounted) return;
    setState(() => _frame = f);
    _frameTimer = Timer(Duration(milliseconds: ms), () {
      if (mounted) setState(() => _frame = _Frame.idle);
    });
  }

  void _undo(ScanEntry e) {
    setState(() {
      e.undo();
      if (e.isEmpty) _entries.remove(e);
    });
  }

  void _showDebug() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Diagnostica',
                style: TextStyle(
                    color: AppColors.gold,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text('Ultimo testo letto dalla fotocamera:',
                style: TextStyle(color: AppColors.textDim)),
            const SizedBox(height: 4),
            SelectableText(_lastOcr.isEmpty ? '(niente)' : _lastOcr,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            const SizedBox(height: 16),
            const Text('Registro:', style: TextStyle(color: AppColors.textDim)),
            const SizedBox(height: 4),
            SelectableText(
              DebugLog.lines.isEmpty ? '(vuoto)' : DebugLog.lines.join('\n'),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------- UI

  Color get _frameColor {
    switch (_frame) {
      case _Frame.ok:
        return AppColors.ok;
      case _Frame.error:
        return AppColors.danger;
      case _Frame.idle:
        return AppColors.gold;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(flex: 5, child: _cameraArea()),
        _buildBanner(),
        Expanded(flex: 3, child: _buildList()),
      ],
    );
  }

  Widget _previewWidget() {
    final c = _controller;
    if (_cameraError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_cameraError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textDim)),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _startCamera,
                child: const Text('Riprova'),
              ),
            ],
          ),
        ),
      );
    }
    if (c == null || !c.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    final size = c.value.previewSize;
    if (size == null) return CameraPreview(c);
    return ClipRect(
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: size.height,
            height: size.width,
            child: CameraPreview(c),
          ),
        ),
      ),
    );
  }

  Widget _cameraArea() {
    return Container(
      color: Colors.black,
      child: LayoutBuilder(builder: (context, box) {
        final fw =
            math.min(box.maxWidth * 0.62, box.maxHeight * 0.88 * 59 / 86);
        final fh = fw * 86 / 59;
        final color = _frameColor;
        return Stack(
          children: [
            Positioned.fill(child: _previewWidget()),
            if (_controller != null)
              Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: fw,
                  height: fh,
                  decoration: BoxDecoration(
                    border: Border.all(color: color, width: 3),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Container(
                        width: fw * 0.4,
                        height: 18,
                        decoration: BoxDecoration(
                          border: Border.all(color: color, width: 1),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                icon: const Icon(Icons.bug_report_outlined),
                color: Colors.white70,
                tooltip: 'Diagnostica',
                onPressed: _showDebug,
              ),
            ),
          ],
        );
      }),
    );
  }

  String _langLabel(String? lang) => lang == 'it' ? 'IT' : 'EN';

  Widget _thumb(CardInfo card) {
    final url = card.imageUrl;
    if (url == null) return const SizedBox(width: 44, height: 64);
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Image.network(
        url,
        width: 44,
        height: 64,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const SizedBox(width: 44, height: 64),
      ),
    );
  }

  Widget _buildBanner() {
    Widget child;
    if (_banner == _Banner.searching) {
      child = Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Text(_bannerMsg),
        ],
      );
    } else if (_banner == _Banner.success && _bannerCard != null) {
      final card = _bannerCard!;
      child = Row(
        children: [
          _thumb(card),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Aggiunta, copia ${_langLabel(_bannerLang)} +1',
                    style:
                        const TextStyle(color: AppColors.ok, fontSize: 12)),
                const SizedBox(height: 2),
                Text(
                  (card.nameIt == null || card.nameIt!.isEmpty)
                      ? '(nome italiano mancante)'
                      : card.nameIt!,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
                Text(card.nameEn,
                    style: const TextStyle(color: AppColors.textDim)),
                Text(_bannerCode ?? '',
                    style: const TextStyle(color: AppColors.gold, fontSize: 12)),
              ],
            ),
          ),
        ],
      );
    } else if (_banner == _Banner.error) {
      child = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_bannerTitle,
              style: const TextStyle(
                  color: AppColors.danger, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(_bannerMsg, style: const TextStyle(color: AppColors.textDim)),
          const SizedBox(height: 6),
          OutlinedButton(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    "L'aggiunta manuale arriva con il database, nel prossimo pacchetto."),
              ),
            ),
            child: const Text('Aggiungi a mano'),
          ),
        ],
      );
    } else if (_banner == _Banner.duplicate && _bannerCard != null) {
      final card = _bannerCard!;
      child = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            (card.nameIt == null || card.nameIt!.isEmpty)
                ? card.nameEn
                : card.nameIt!,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            'Già scansionata (copia ${_langLabel(_bannerLang)}). Aggiungerne un\'altra?',
            style: const TextStyle(color: AppColors.textDim),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () => _answerDuplicate(true),
                  child: const Text('Sì'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _answerDuplicate(false),
                  child: const Text('No'),
                ),
              ),
            ],
          ),
        ],
      );
    } else {
      child = const Center(
        child: Text(
          'Inquadra la carta. Il codice va in basso a sinistra, nel riquadro piccolo.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textDim),
        ),
      );
    }

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 96),
      padding: const EdgeInsets.all(12),
      color: AppColors.surface,
      child: child,
    );
  }

  Widget _buildList() {
    if (_entries.isEmpty) {
      return const Center(
        child: Text('Le carte scansionate compariranno qui.',
            style: TextStyle(color: AppColors.textDim)),
      );
    }
    return ListView.builder(
      itemCount: _entries.length,
      itemBuilder: (context, i) {
        final e = _entries[i];
        final nameIt = (e.card.nameIt == null || e.card.nameIt!.isEmpty)
            ? '—'
            : e.card.nameIt!;
        return ListTile(
          dense: true,
          title: Text(nameIt, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${e.card.nameEn}  ·  ${e.code}',
              maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('IT ×${e.qtyIt}  EN ×${e.qtyEn}',
                  style: const TextStyle(color: AppColors.gold)),
              IconButton(
                icon: const Icon(Icons.undo),
                tooltip: 'Annulla una copia',
                onPressed: () => _undo(e),
              ),
            ],
          ),
        );
      },
    );
  }
}
