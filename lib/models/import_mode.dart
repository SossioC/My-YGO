/// Come importare un file di backup.
enum ImportMode {
  /// Cancella tutto quello che c'è e usa il file.
  replace,

  /// Aggiunge al contenuto attuale sommando le copie delle carte già presenti.
  mergeSum,

  /// Aggiunge al contenuto attuale tenendo, per ogni lingua, il numero di copie maggiore.
  mergeMax,
}
