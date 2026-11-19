using System.Collections.Generic;

namespace CodeBrix.WebPlatform.WasmShrink;

/// <summary>
/// The choices for one <see cref="WasmShrinkTool.ShrinkAsync"/> call. The defaults give the
/// smallest file with debug information removed.
/// </summary>
public class WasmShrinkOptions
{
    /// <summary>The optimization switch to use. Defaults to <see cref="WasmShrinkLevel.Oz"/>.</summary>
    public WasmShrinkLevel Level { get; set; } = WasmShrinkLevel.Oz;

    /// <summary>
    /// When <c>false</c> (the default) debug information is removed from the output
    /// (<c>--strip-debug</c>). When <c>true</c> it is kept (<c>--debuginfo</c>), which also keeps
    /// function names so a failure in the browser shows a readable stack.
    /// </summary>
    public bool KeepDebugInfo { get; set; }

    /// <summary>
    /// Further wasm-opt arguments, added after the ones this class produces - for example
    /// <c>--enable-bulk-memory</c> for a module that uses that WebAssembly feature.
    /// </summary>
    public IList<string> AdditionalArguments { get; } = new List<string>();
}
