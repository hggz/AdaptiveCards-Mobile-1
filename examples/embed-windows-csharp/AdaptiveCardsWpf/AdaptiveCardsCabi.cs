// AdaptiveCardsCabi.cs
//
// P/Invoke declarations for the @_cdecl symbols exported by
// AdaptiveCardsCABIShared.dll. Mirrors the contract documented in
// ios/Sources/AdaptiveCardsCABI/CABI.swift and
// examples/embed-windows/c_abi/adaptive_cards.h (the C header).
//
// Memory contract reminders (the Swift side allocates with malloc;
// callers MUST free with ac_free):
//   * ac_host_create     -> returns opaque IntPtr; pair with
//                            ac_host_destroy exactly once.
//   * ac_host_render_json -> returns IntPtr to malloc'd UTF-8 C string;
//                            convert with Marshal.PtrToStringUTF8,
//                            then ac_free the original pointer.
//   * ac_host_backend_identifier -> same as render_json.
//   * ac_last_error       -> static-lifetime pointer; DO NOT free.

using System;
using System.Runtime.InteropServices;

namespace AdaptiveCardsWpf;

internal static class AdaptiveCardsCabi
{
    private const string Dll = "AdaptiveCardsCABIShared";

    /// <summary>
    /// Creates a host. <paramref name="hostConfigJson"/> may be null
    /// or empty for default config.
    /// </summary>
    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl,
        CharSet = CharSet.Ansi, EntryPoint = "ac_host_create")]
    public static extern IntPtr CreateHost(
        [MarshalAs(UnmanagedType.LPUTF8Str)] string? hostConfigJson);

    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl,
        EntryPoint = "ac_host_destroy")]
    public static extern void DestroyHost(IntPtr host);

    /// <summary>
    /// Renders an Adaptive Card JSON string to a RenderingNode IR
    /// JSON string. Returned pointer must be freed with
    /// <see cref="Free"/>.
    /// </summary>
    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl,
        EntryPoint = "ac_host_render_json")]
    public static extern IntPtr RenderJson(
        IntPtr host,
        [MarshalAs(UnmanagedType.LPUTF8Str)] string cardJson);

    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl,
        EntryPoint = "ac_host_backend_identifier")]
    public static extern IntPtr BackendIdentifier(IntPtr host);

    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl,
        EntryPoint = "ac_last_error")]
    public static extern IntPtr LastError();

    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl,
        EntryPoint = "ac_free")]
    public static extern void Free(IntPtr ptr);

    /// <summary>
    /// Owning wrapper. Reads the C string at <paramref name="ptr"/>,
    /// frees it via ac_free, returns the managed string copy.
    /// </summary>
    public static string? ReadAndFreeUtf8(IntPtr ptr)
    {
        if (ptr == IntPtr.Zero)
        {
            return null;
        }
        try
        {
            return Marshal.PtrToStringUTF8(ptr);
        }
        finally
        {
            Free(ptr);
        }
    }

    /// <summary>
    /// Returns the most recent error message, or null if there is none.
    /// The Swift side owns this string; do NOT free it.
    /// </summary>
    public static string? PeekLastError()
    {
        var ptr = LastError();
        return ptr == IntPtr.Zero ? null : Marshal.PtrToStringUTF8(ptr);
    }
}
