import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../data/card_repository.dart';
import '../models/card_info.dart';
import '../models/owned_card.dart';
import '../services/card_images.dart';
import '../services/code_parser.dart';
import '../services/debug_log.dart';
import '../services/sounds.dart';
import '../services/ygo_api.dart';
import '../theme.dart';
import '../widgets/card_thumb.dart';
import 'card_edit_page.dart';

enum _Frame { idle, ok, error }

enum _Banner { hint, searching, success, error, duplicate }

/// Una carta scansionata durante questa sessione.
class _SessionItem {
  OwnedCard card;
  final List<String> added = [];
  _SessionItem(this.card);
}

class ScanPage extends StatefulWidget {
  final bool active;

  const ScanPage({super.key, required this.active});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> with WidgetsBindingObserver {
  static const String _defaultHint =
      'Inquadra la carta. Il codice va in basso a sinistra, nel riquadro piccolo.';
  static const String _struggleHint =
      'Non riesco a leggere il codice: avvicina un poco la carta, tienila ferma ed evita i riflessi. Puoi anche toccare lo schermo per mettere a fuoco.';

  final TextRecognizer _recognizer =
      TextRecognizer(script: TextRecognitionScript.latin);
  final YgoApi _api = YgoApi.instance;
  final Sounds _sounds = Sounds();
  final CardRepository _repo = CardRepository.instance;
  final List<_SessionItem> _session = [];

  CameraController? _controller;
  CameraDescription? _camera;
  bool _starting = false;
  String? _cameraError;

  ResolutionPreset _preset = ResolutionPreset.ultraHigh;
  double _zoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;

  bool _processing = false;
  int _lastFrameMs = 0;
  bool _formatLogged = false;

  final Map<String, List<int>> _hits = {};
  String? _lockedCode;
  int _lockedSeenMs = 0;
  int _lastCodeSeenMs = 0;
  int? _noTextSince;
  int? _unreadableSince;
  bool _unreadableErrored = false;
  String _lastOcr = '';

  _Frame _frame = _Frame.idle;
  Timer? _frameTimer;

  _Banner _banner = _Banner.hint;
  String _hintMsg = _defaultHint;
  String _bannerTitle = '';
  String _bannerMsg = '';
  CardInfo? _bannerCard;
  String? _bannerLang;
  String? _bannerCode;
  String _bannerTotals = '';
  String? _lastFailedCode;

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
        _preset,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );
      await ctrl.initialize();
      try {
        await ctrl.setFocusMode(FocusMode.auto);
      } catch (_) {}
      try {
        _minZoom = await ctrl.getMinZoomLevel();
        _maxZoom = math.min(await ctrl.getMaxZoomLevel(), 4.0);
        _zoom = _zoom.clamp(_minZoom, _maxZoom).toDouble();
        await ctrl.setZoomLevel(_zoom);
      } catch (_) {}
      if (!mounted || !widget.active) {
        await ctrl.dispose();
        return;
      }
      _camera = cam;
      _controller = ctrl;
      await ctrl.startImageStream(_onFrame);
      DebugLog.add(
          'Fotocamera avviata: ${ctrl.value.previewSize}, qualità $_preset, zoom $_zoom');
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

  Future<void> _restartCamera() async {
    await _stopCamera();
    await _startCamera();
  }

  Future<void> _setZoom(double z) async {
    _zoom = z;
    try {
      await _controller?.setZoomLevel(z);
    } catch (_) {}
  }

  Future<void> _focusAt(TapDownDetails d, Size area) async {
    final c = _controller;
    if (c == null) return;
    final p = Offset(
      (d.localPosition.dx / area.width).clamp(0.0, 1.0).toDouble(),
      (d.localPosition.dy / area.height).clamp(0.0, 1.0).toDouble(),
    );
    try {
      await c.setFocusPoint(p);
      await c.setExposurePoint(p);
    } catch (_) {}
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
        format: InputImageFormat.nv21,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  // -------------------------------------------------------------- scanning

  Future<void> _onFrame(CameraImage image) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_processing || now - _lastFrameMs < 250) return;
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

  void _setHint(String msg) {
    if (_hintMsg == msg) return;
    if (!mounted) return;
    setState(() => _hintMsg = msg);
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

      // La carta è uscita dall'inquadratura: sblocca.
      if (_lockedCode != null) {
        final gone = _noTextSince != null && now - _noTextSince! > 1000;
        final stale = now - _lastCodeSeenMs > 4000;
        if (gone || stale) {
          _lockedCode = null;
          _hits.clear();
        }
        return;
      }

      if (!hasText) {
        _unreadableSince = null;
        _unreadableErrored = false;
        _setHint(_defaultHint);
        return;
      }

      _unreadableSince ??= now;
      final elapsed = now - _unreadableSince!;
      if (elapsed > 1800 && _banner == _Banner.hint) {
        _setHint(_struggleHint);
      }
      if (elapsed > 5000 && !_unreadableErrored) {
        _unreadableErrored = true;
        DebugLog.add('NON LETTO. Testo visto: $_lastOcr');
        _fail('Codice non letto', 'Avvicina la carta o aggiungila a mano.');
      }
      return;
    }

    // Almeno un codice trovato.
    _unreadableSince = null;
    _unreadableErrored = false;
    _noTextSince = null;
    _lastCodeSeenMs = now;
    _setHint(_defaultHint);

    for (final c in codes) {
      _hits.putIfAbsent(c.raw, () => []).add(now);
    }
    for (final list in _hits.values) {
      list.removeWhere((t) => now - t > 2500);
    }
    _hits.removeWhere((k, v) => v.isEmpty);

    if (_lockedCode != null && codes.any((c) => c.raw == _lockedCode)) {
      _lockedSeenMs = now;
      return;
    }
    // La carta di prima è ancora lì: un codice diverso è quasi sempre una lettura sbagliata.
    if (_lockedCode != null && now - _lockedSeenMs < 1000) return;

    // Il codice vale se letto almeno 2 volte negli ultimi istanti.
    String? best;
    int bestHits = 0;
    _hits.forEach((k, v) {
      if (v.length > bestHits) {
        best = k;
        bestHits = v.length;
      }
    });
    if (best == null || bestHits < 2) return;

    final chosen = codes.firstWhere((c) => c.raw == best,
        orElse: () => codes.first);
    _hits.clear();
    _lockedCode = chosen.raw;
    _lockedSeenMs = now;
    await _resolve(chosen);
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
    final info = res.card;
    if (info == null) {
      _lastFailedCode = code.raw;
      _fail('Carta non trovata', 'Codice letto: ${code.raw}', manual: true);
      return;
    }

    final already = _session.any(
        (s) => s.card.ygoId == info.id && s.added.contains(lang));
    if (already) {
      _sounds.playOk();
      setState(() {
        _pendingCard = info;
        _pendingLang = lang;
        _pendingCode = code.raw;
        _banner = _Banner.duplicate;
        _bannerCard = info;
        _bannerLang = lang;
        _bannerCode = code.raw;
      });
      _flash(_Frame.ok);
      return;
    }

    await _addCopy(info, lang, code.raw);
  }

  Future<void> _addCopy(CardInfo info, String lang, String code) async {
    OwnedCard owned;
    try {
      owned = await _repo.addCopy(info, lang, code);
    } catch (e) {
      DebugLog.add('Errore database: $e');
      _fail('Errore di salvataggio', '$e');
      return;
    }
    if (!mounted) return;

    final idx = _session.indexWhere((s) => s.card.ygoId == info.id);
    _SessionItem item;
    if (idx >= 0) {
      item = _session.removeAt(idx);
      item.card = owned;
    } else {
      item = _SessionItem(owned);
    }
    item.added.add(lang);

    _sounds.playOk();
    setState(() {
      _session.insert(0, item);
      _pendingCard = null;
      _banner = _Banner.success;
      _bannerCard = info;
      _bannerLang = lang;
      _bannerCode = code;
      _bannerTotals = 'In collezione: IT ×${owned.qtyIt}  EN ×${owned.qtyEn}';
    });
    _flash(_Frame.ok);
    _cacheImage(owned);
  }

  Future<void> _cacheImage(OwnedCard owned) async {
    final id = owned.id;
    final ygoId = owned.ygoId;
    if (id == null || ygoId == null) return;
    if (owned.imagePath != null) return;
    final path = await CardImages.download(ygoId, owned.imageUrl);
    if (path != null) {
      await _repo.setImagePath(id, path);
      owned.imagePath = path;
    }
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

  Future<void> _undo(_SessionItem it) async {
    if (it.added.isEmpty) return;
    final lang = it.added.removeLast();
    final id = it.card.id;
    OwnedCard? updated;
    if (id != null) updated = await _repo.removeCopy(id, lang);
    if (!mounted) return;
    setState(() {
      if (updated != null) it.card = updated;
      if (it.added.isEmpty || updated == null) _session.remove(it);
    });
  }

  void _addManually() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CardEditPage(prefillCode: _lastFailedCode),
      ),
    );
  }

  void _showSettings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          builder: (ctx, scroll) => ListView(
            controller: scroll,
            padding: const EdgeInsets.all(16),
            children: [
              const Text('Impostazioni scansione',
                  style: TextStyle(
                      color: AppColors.gold,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text('Qualità di lettura',
                  style: TextStyle(color: AppColors.textDim)),
              const SizedBox(height: 6),
              SegmentedButton<ResolutionPreset>(
                segments: const [
                  ButtonSegment(
                      value: ResolutionPreset.veryHigh, label: Text('Alta 1080p')),
                  ButtonSegment(
                      value: ResolutionPreset.ultraHigh,
                      label: Text('Massima 4K')),
                ],
                selected: {_preset},
                onSelectionChanged: (s) {
                  setSheet(() => _preset = s.first);
                  setState(() {});
                  _restartCamera();
                },
              ),
              const SizedBox(height: 4),
              const Text(
                  'Massima legge meglio i codici piccoli ma è più pesante. Se il telefono rallenta, scegli Alta.',
                  style: TextStyle(color: AppColors.textDim, fontSize: 12)),
              const SizedBox(height: 16),
              Text('Zoom: ${_zoom.toStringAsFixed(1)}x',
                  style: const TextStyle(color: AppColors.textDim)),
              Slider(
                value: _zoom.clamp(_minZoom, _maxZoom).toDouble(),
                min: _minZoom,
                max: _maxZoom > _minZoom ? _maxZoom : _minZoom + 0.1,
                onChanged: (v) {
                  setSheet(() => _zoom = v);
                  _setZoom(v);
                },
              ),
              const Divider(),
              const Text('Diagnostica',
                  style: TextStyle(
                      color: AppColors.gold,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Ultimo testo letto dalla fotocamera:',
                  style: TextStyle(color: AppColors.textDim)),
              const SizedBox(height: 4),
              SelectableText(_lastOcr.isEmpty ? '(niente)' : _lastOcr,
                  style:
                      const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              const SizedBox(height: 12),
              const Text('Registro:',
                  style: TextStyle(color: AppColors.textDim)),
              const SizedBox(height: 4),
              SelectableText(
                DebugLog.lines.isEmpty ? '(vuoto)' : DebugLog.lines.join('\n'),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ],
          ),
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
        Expanded(flex: 6, child: _cameraArea()),
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
            math.min(box.maxWidth * 0.9, box.maxHeight * 0.94 * 59 / 86);
        final fh = fw * 86 / 59;
        final color = _frameColor;
        final area = Size(box.maxWidth, box.maxHeight);
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => _focusAt(d, area),
                child: _previewWidget(),
              ),
            ),
            if (_controller != null)
              IgnorePointer(
                child: Center(
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
              ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                icon: const Icon(Icons.tune),
                color: Colors.white70,
                tooltip: 'Impostazioni e diagnostica',
                onPressed: _showSettings,
              ),
            ),
          ],
        );
      }),
    );
  }

  String _langLabel(String? lang) => lang == 'it' ? 'IT' : 'EN';

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
          CardThumb(url: card.imageSmallUrl ?? card.imageUrl),
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
                      ? card.nameEn
                      : card.nameIt!,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
                if (card.nameIt != null && card.nameIt!.isNotEmpty)
                  Text(card.nameEn,
                      style: const TextStyle(color: AppColors.textDim)),
                Text('${_bannerCode ?? ''}  ·  $_bannerTotals',
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
            onPressed: _addManually,
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
      child = Center(
        child: Text(
          _hintMsg,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textDim),
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
    if (_session.isEmpty) {
      return const Center(
        child: Text('Le carte scansionate compariranno qui.',
            style: TextStyle(color: AppColors.textDim)),
      );
    }
    return ListView.builder(
      itemCount: _session.length,
      itemBuilder: (context, i) {
        final s = _session[i];
        final c = s.card;
        return ListTile(
          dense: true,
          leading: CardThumb(
              path: c.imagePath, url: c.imageUrl, width: 30, height: 44),
          title: Text(c.displayName,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
              c.nameIt.isEmpty ? c.code : '${c.nameEn}  ·  ${c.code}',
              maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('IT ×${c.qtyIt}  EN ×${c.qtyEn}',
                  style: const TextStyle(color: AppColors.gold)),
              IconButton(
                icon: const Icon(Icons.undo),
                tooltip: 'Annulla l\'ultima copia aggiunta',
                onPressed: () => _undo(s),
              ),
            ],
          ),
        );
      },
    );
  }
}
