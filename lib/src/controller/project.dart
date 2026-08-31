part of 'node_editor_controller.dart';

/// Writes an encoded document wherever the host keeps them.
///
/// Returns whether it was actually written: false for a save the user backed
/// out of, which is not a failure and must not mark the document clean.
typedef GraphDocumentSink = Future<bool> Function(Map<String, Object?> json);

/// Produces an encoded document, or null when there is nothing to open —
/// a file picker the user dismissed, say.
typedef GraphDocumentSource = Future<Map<String, Object?>?> Function();

/// The document as a whole: what is open, whether it has been saved, and the
/// conversions to and from JSON.
///
/// The package still does no I/O. [save] and [load] route through the [sink]
/// and [source] the host supplies, so a file picker, a database or a network
/// call all fit without this file knowing which.
class NodeEditorProject {
  NodeEditorProject(this._controller, {NodeGraphCodec? codec}) : _codec = codec;

  final NodeEditorController _controller;
  final NodeGraphCodec? _codec;

  /// Where [save] writes. Assign before calling it.
  GraphDocumentSink? sink;

  /// Where [load] reads. Assign before calling it.
  GraphDocumentSource? source;

  /// Metadata written into every document — a title, most often.
  ///
  /// Adopted from a document when one is opened, so a round trip keeps it.
  Map<String, Object?> meta = const <String, Object?>{};

  /// The host application's own version, recorded in the document as a
  /// breadcrumb. Written and never read back.
  String? appVersion;

  NodeGraph? _savedGraph;
  DateTime? _lastSaved;

  /// The codec documents are converted with.
  ///
  /// Falls back to a plain one when the controller was given none. A codec
  /// without prototypes still round-trips correctly; all it loses is the
  /// chance to leave out data it could prove was derived.
  NodeGraphCodec get codec => _codec ?? const NodeGraphCodec();

  bool get canSave => sink != null;
  bool get canLoad => source != null;

  /// When the document was last written, or null if it never has been.
  DateTime? get lastSaved => _lastSaved;

  /// Whether the graph has moved on since it was last saved, opened, or
  /// constructed.
  ///
  /// Compared by identity, which the immutable graph makes exact rather than
  /// approximate: every edit produces a new snapshot, and undoing back to the
  /// saved state restores the very snapshot that was saved, so it reports
  /// clean again. Retyping a value back by hand does not — that is a new
  /// snapshot, and the honest answer to "is there something unwritten" is yes.
  bool get isDirty => !identical(_controller._graph, _savedGraph);

  /// Declares the current graph as the saved one, for a host that wrote the
  /// document itself rather than through [save].
  void markSaved() {
    if (identical(_controller._graph, _savedGraph)) return;
    _savedGraph = _controller._graph;
    _lastSaved = DateTime.now();
    _controller._notify();
  }

  // -------------------------------------------------------------- documents

  /// The editor's current state as a document, ready to encode.
  GraphDocument get document => GraphDocument(
    graph: _controller._graph,
    viewport: _controller.camera.viewport,
    meta: meta,
    appVersion: appVersion,
  );

  Map<String, Object?> encode() => codec.encode(document);

  /// The document as JSON text, indented for a human to read.
  ///
  /// Pass an empty [indent] for the compact form a file or a network call
  /// wants.
  String encodeToJson({String indent = '  '}) => indent.isEmpty
      ? jsonEncode(encode())
      : JsonEncoder.withIndent(indent).convert(encode());

  /// Reads a document without touching the editor.
  ///
  /// Throws [GraphDocumentException] on anything it cannot read. Decoding
  /// separately from [open] is the whole point: a document that fails here
  /// leaves the one on screen exactly as it was.
  GraphDocument decode(Map<String, Object?> json) => codec.decode(json);

  /// [decode], from JSON text. Throws [FormatException] on text that is not
  /// JSON at all.
  GraphDocument decodeJson(String text) {
    final json = jsonDecode(text);
    if (json is! Map) {
      throw const FormatException('expected a JSON object at the top level');
    }
    return decode(Map<String, Object?>.from(json));
  }

  /// Swaps [document] in as the open one.
  ///
  /// The history is dropped — an undo across a load would restore half of a
  /// document that is no longer open — and the result counts as saved, since
  /// it is exactly what storage holds.
  ///
  /// The camera moves only if the document says where it was left. A caller
  /// that wants to frame the content instead checks
  /// [GraphDocument.viewport] for null and calls `fitToContent` itself, which
  /// needs a viewport size only the widget layer knows.
  void open(GraphDocument document, {bool restoreViewport = true}) {
    _controller.replaceGraph(document.graph, recordHistory: false);
    _controller.selection.clear();
    meta = document.meta;

    final viewport = document.viewport;
    if (restoreViewport && viewport != null) {
      _controller.camera.viewport = viewport;
    }
    _savedGraph = _controller._graph;
    _lastSaved = null;
    _controller._notify();
  }

  /// Starts a new document, empty unless [graph] says otherwise.
  ///
  /// A fresh document counts as saved: there is nothing in it to lose.
  void reset([NodeGraph? graph]) {
    _controller.replaceGraph(graph ?? NodeGraph.empty, recordHistory: false);
    _controller.selection.clear();
    meta = const <String, Object?>{};
    _savedGraph = _controller._graph;
    _lastSaved = null;
    _controller._notify();
  }

  // ---------------------------------------------------------------- storage

  /// Encodes the document and hands it to [sink].
  ///
  /// Returns what the sink reported. An edit made while the write was in
  /// flight leaves the document dirty, because what reached storage is not
  /// what is on screen any more.
  Future<bool> save() async {
    final write = sink;
    if (write == null) {
      throw StateError(
        'NodeEditorProject.save needs somewhere to write: assign '
        'controller.project.sink first.',
      );
    }
    final snapshot = _controller._graph;
    if (!await write(codec.encode(document))) return false;
    _savedGraph = snapshot;
    _lastSaved = DateTime.now();
    _controller._notify();
    return true;
  }

  /// Reads a document from [source] and opens it.
  ///
  /// Returns the document, or null when the source had nothing to give — a
  /// picker the user dismissed. Decoding happens before anything is replaced,
  /// so a [GraphDocumentException] leaves the open document on screen; that is
  /// the failure mode this whole shape exists to make impossible.
  Future<GraphDocument?> load({bool restoreViewport = true}) async {
    final read = source;
    if (read == null) {
      throw StateError(
        'NodeEditorProject.load needs somewhere to read: assign '
        'controller.project.source first.',
      );
    }
    final json = await read();
    if (json == null) return null;

    final document = decode(json);
    open(document, restoreViewport: restoreViewport);
    return document;
  }
}
