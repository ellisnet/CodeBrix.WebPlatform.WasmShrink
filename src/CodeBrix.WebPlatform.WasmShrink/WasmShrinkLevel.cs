namespace CodeBrix.WebPlatform.WasmShrink;

/// <summary>
/// How hard wasm-opt works on a WebAssembly file, and whether it favours a smaller file or
/// faster code. Each value is one of wasm-opt's own optimization switches.
/// </summary>
public enum WasmShrinkLevel
{
    /// <summary>No optimization passes (<c>-O0</c>); the file is only read and written back.</summary>
    O0,

    /// <summary>Quick, light optimization (<c>-O1</c>).</summary>
    O1,

    /// <summary>Most optimizations, favouring speed (<c>-O2</c>).</summary>
    O2,

    /// <summary>Slower, more thorough optimization for speed (<c>-O3</c>).</summary>
    O3,

    /// <summary>The most thorough optimization for speed (<c>-O4</c>); the slowest to run.</summary>
    O4,

    /// <summary>Optimizes for a smaller file (<c>-Os</c>).</summary>
    Os,

    /// <summary>Optimizes hardest for the smallest file (<c>-Oz</c>). The default.</summary>
    Oz,
}
