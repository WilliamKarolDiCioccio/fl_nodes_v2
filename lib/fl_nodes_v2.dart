/// A reusable, pannable and zoomable node graph editor.
///
/// The package splits into three layers, and each can be used on its own:
///
/// * **Model** — [NodeGraph], [GraphNode], [NodePort] and [NodeConnection] are
///   immutable value types with no Flutter dependency beyond geometry.
/// * **Controller** — [NodeEditorController] owns the current graph, and
///   reaches the rest through subsystems: [NodeEditorHistory],
///   [NodeEditorSelection], [NodeEditorCamera], [NodeEditorLayout],
///   [NodeEditorClipboard], [NodeEditorProject] and [NodeEditorRunner].
/// * **View** — [NodeEditor] renders the canvas and handles interaction, and
///   delegates the look of each node to a `nodeBuilder` you supply.
library;

export 'src/controller/graph_edit.dart'
    show GraphEdit, GraphEditKind, GraphEditGuard, GraphEditListener;
export 'src/controller/node_editor_controller.dart'
    show
        ConnectionValidator,
        GraphDocumentSink,
        GraphDocumentSource,
        GraphFragment,
        GraphLayout,
        AbsentPayload,
        DiagnosticRaised,
        GraphPayload,
        GraphRun,
        GraphRunDiagnostic,
        GraphRunEvent,
        GraphRunException,
        GraphRunIssue,
        GraphRunListener,
        GraphRunRecorder,
        GraphTraceValue,
        LogEmitted,
        MemoHit,
        NodeFinished,
        NodeStarted,
        PresentPayload,
        RunFinished,
        RunStarted,
        WithheldPayload,
        NodeEditorCamera,
        NodeEditorClipboard,
        NodeEditorController,
        NodeEditorEmphasis,
        NodeEditorHistory,
        NodeEditorLayout,
        NodeEditorProject,
        NodeEditorRunner,
        NodeEditorSelection,
        NodeRunState;
export 'src/collections/spatial_hash_grid.dart' show SpatialHashGrid;
export 'src/geometry/connection_path.dart' show ConnectionPath, PathArrow;
export 'src/geometry/connection_router.dart'
    show ConnectionEndpoints, ConnectionRouter;
export 'src/geometry/node_geometry.dart' show NodeGeometry;
export 'src/geometry/viewport_transform.dart' show ViewportTransform;
export 'src/model/graph_emphasis.dart' show GraphEmphasis;
export 'src/model/graph_node.dart' show GraphNode;
export 'src/model/node_comment.dart' show NodeComment;
export 'src/model/node_connection.dart' show NodeConnection;
export 'src/model/node_group.dart' show NodeGroup;
export 'src/model/node_graph.dart' show NodeGraph;
export 'src/model/node_port.dart'
    show NodePort, PortDirection, PortKind, PortSide;
export 'src/model/payload_equality.dart' show payloadEquals, payloadHash;
export 'src/model/port_ref.dart' show PortRef;
export 'src/prototype/link_prototype.dart'
    show
        DerivedLinkLabel,
        EditableLinkLabel,
        LinkLabel,
        LinkLabelBuilder,
        LinkPrototype,
        LinkResolutionContext;
export 'src/prototype/node_execution.dart'
    show GraphLogEntry, GraphLogLevel, NodeExecutionContext, NodeExecutor;
export 'src/prototype/node_prototype.dart'
    show
        DynamicFieldFamily,
        DynamicPortFamily,
        FieldFamily,
        NodeField,
        NodePrototype,
        PortFamily,
        StaticFieldFamily,
        StaticPortFamily;
export 'src/prototype/node_prototype_registry.dart'
    show
        NodeFieldGroup,
        NodePrototypeRegistry,
        PrototypeDivergenceHandler,
        PrototypeResolution;
export 'src/prototype/node_resolution.dart'
    show
        FieldFamilyBuilder,
        NodeFieldMerge,
        NodeFieldMergeContext,
        NodeFields,
        NodeHeightResolver,
        NodePortRemoval,
        NodeResolutionContext,
        PortFamilyBuilder,
        PortRemoval,
        PortRemovalHandler;
export 'src/prototype/port_family_builders.dart' show PortFamilies;
export 'src/menus/node_editor_menu_host.dart' show NodeEditorMenuHost;
export 'src/menus/node_submenu_button.dart' show CascadeSide, NodeSubmenuButton;
export 'src/menus/node_editor_menus.dart'
    show
        NodeEditorMenus,
        NodeMenuBuilder,
        NodeMenuCanvasTarget,
        NodeMenuConnectionTarget,
        NodeMenuGroupTarget,
        NodeMenuNodeTarget,
        NodeMenuPortTarget,
        NodeMenuRequest,
        NodeMenuTarget;
export 'src/menus/node_menu_entry.dart' show NodeMenuEntry;
export 'src/minimap/minimap_config.dart' show MinimapConfig, MinimapNodeColor;
export 'src/minimap/minimap_controller.dart' show MinimapController;
export 'src/minimap/minimap_painter.dart' show MinimapPainter;
export 'src/minimap/minimap_projection.dart'
    show MinimapProjection, minimapNodeColor, minimapShadeBands;
export 'src/minimap/minimap_scene.dart' show MinimapScene;
export 'src/painting/connection_label.dart'
    show ConnectionCaption, ConnectionLabel;
export 'src/painting/connection_layout.dart'
    show ConnectionGeometry, ConnectionLayout, arrowheadSize, arrowheadsPath;
export 'src/painting/connections_painter.dart' show ConnectionsPainter;
export 'src/painting/emphasis_painter.dart' show EmphasisPainter;
export 'src/painting/grid_painter.dart' show GridPainter;
export 'src/painting/grid_shader.dart' show GridShader;
export 'src/painting/ports_painter.dart' show PortsPainter;
export 'src/painting/overlay_painter.dart'
    show OverlayPainter, PendingConnection;
export 'src/serialization/document_exceptions.dart'
    show
        GraphDocumentException,
        GraphDocumentFormatException,
        GraphDocumentVersionException,
        UnencodablePayloadException;
export 'src/serialization/document_migrations.dart'
    show GraphDocumentMigration, GraphDocumentMigrations;
export 'src/serialization/graph_document.dart' show GraphDocument;
export 'src/serialization/node_graph_codec.dart'
    show NodeGraphCodec, PortStorage;
export 'src/serialization/payload_codecs.dart'
    show PayloadCodec, PayloadCodecs, PayloadDecoder, PayloadEncoder;
export 'src/theme/node_editor_theme.dart' show NodeEditorTheme;
export 'src/widgets/connection_label_editor.dart'
    show showConnectionLabelEditor;
export 'src/widgets/edge_scroll_config.dart' show EdgeScrollConfig;
export 'src/widgets/node_editor.dart'
    show CanvasDragBehavior, NodeEditor, NodeEditorState;
export 'src/widgets/group_name_editor.dart' show showGroupNameEditor;
export 'src/widgets/node_description_dialog.dart' show showNodeDescription;
export 'src/widgets/node_editor_scope.dart' show NodeEditorScope;
export 'src/widgets/node_view.dart' show NodeRenderState, NodeWidgetBuilder;
