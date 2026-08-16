# md4a

md4a is a native Markdown document application. Its purpose is to make a Markdown file feel like a PDF in a system viewer while remaining directly editable.

## Language

**Document**:
An ordinary UTF-8 Markdown file opened or created by the user. The file remains the source of truth and has no md4a-specific wrapper format.
_Avoid_: Project, notebook

**Preview**:
The rendered, read-only presentation of the current Document.
_Avoid_: Output, webpage

**Renderer package**:
A downloaded, signed bundle of declarative metadata and sandboxed web assets that adds Preview support for a fenced language or another explicitly declared Markdown construct.
_Avoid_: Native plugin, executable plugin

**Renderer**:
A built-in or package-provided transformation from one declared Markdown construct into Preview content.
_Avoid_: Extension, parser

**Package catalog**:
A signed index from which users discover and download Renderer packages.
_Avoid_: Plugin store, marketplace
