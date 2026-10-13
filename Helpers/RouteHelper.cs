using NurseStationTablet.Models;

namespace NurseStationTablet.Helpers;

/// <summary>
/// Helper to build query strings and route values that preserve launch context
/// (ModCd, SubModCode, User, Location, CoCd, DivCd, LocCd, Ref) through navigation.
/// </summary>
public static class RouteHelper
{
    /// <summary>Build route values dictionary from LaunchContext for passing through URLs.</summary>
    public static Dictionary<string, string> Build(LaunchContext context)
    {
        return context.RouteValues();
    }

    /// <summary>Build a query string from route values.</summary>
    public static string BuildQueryString(Dictionary<string, string> routeValues)
    {
        if (routeValues == null || routeValues.Count == 0) return "";
        var parts = routeValues
            .Where(kv => !string.IsNullOrWhiteSpace(kv.Value))
            .Select(kv => $"{Uri.EscapeDataString(kv.Key)}={Uri.EscapeDataString(kv.Value)}");
        var qs = string.Join("&", parts);
        return string.IsNullOrEmpty(qs) ? "" : "?" + qs;
    }

    /// <summary>Get the exit URL that returns control to the host dashboard.</summary>
    public static string GetExitUrl(string legacySubMenuPath, string? exitUserId = null)
    {
        var path = legacySubMenuPath ?? "";
        if (string.IsNullOrEmpty(path)) return "";
        if (!string.IsNullOrEmpty(exitUserId)) path += "?uid=" + Uri.EscapeDataString(exitUserId);
        return path;
    }
}
