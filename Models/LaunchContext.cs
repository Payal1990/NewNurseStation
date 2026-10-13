namespace NurseStationTablet.Models;

/// <summary>
/// Context passed in from the host HIS application when it launches the Nurse Station module.
/// Two launch shapes are supported: individually named params and a single "ref" param (the real launcher format).
/// This context is carried through every module call to maintain consistent addressing.
/// </summary>
public class LaunchContext
{
    public string? ModCd { get; set; }
    public string? SubModCode { get; set; }
    public string? User { get; set; }
    public string? Location { get; set; }
    public string? CoCd { get; set; }
    public int? DivCd { get; set; }
    public int? LocCd { get; set; }
    public string? Ref { get; set; }

    public bool HasHostContext => !string.IsNullOrWhiteSpace(ModCd)
        || !string.IsNullOrWhiteSpace(SubModCode)
        || !string.IsNullOrWhiteSpace(Location)
        || !string.IsNullOrWhiteSpace(CoCd)
        || DivCd.HasValue
        || LocCd.HasValue
        || !string.IsNullOrWhiteSpace(Ref);

    /// <summary>Username parsed from the "ref" launch param (3rd field from end).</summary>
    public string? RefUser
    {
        get
        {
            if (string.IsNullOrWhiteSpace(Ref)) return null;
            var fields = Ref.Split(';');
            if (fields.Length < 3) return null;
            var value = fields[^3].Trim();
            return string.IsNullOrWhiteSpace(value) ? null : value;
        }
    }

    /// <summary>Explicit "user" param wins; otherwise falls back to the username from "ref".</summary>
    public string DisplayUser => !string.IsNullOrWhiteSpace(User) ? User! : (RefUser ?? "SOFSCRIPT");

    /// <summary>Login/company id parsed from the "ref" launch param (field 0).</summary>
    public string? RefUserId
    {
        get
        {
            if (string.IsNullOrWhiteSpace(Ref)) return null;
            var value = Ref.Split(';')[0].Trim();
            return string.IsNullOrWhiteSpace(value) ? null : value;
        }
    }

    /// <summary>The id to send back to the host dashboard on Exit.</summary>
    public string? ExitUserId => RefUserId ?? User;

    /// <summary>Route values for preserving launch parameters through navigation.</summary>
    public Dictionary<string, string> RouteValues()
    {
        var values = new Dictionary<string, string>();
        if (!string.IsNullOrWhiteSpace(ModCd)) values["modcd"] = ModCd!;
        if (!string.IsNullOrWhiteSpace(SubModCode)) values["submodcode"] = SubModCode!;
        if (!string.IsNullOrWhiteSpace(User)) values["user"] = User!;
        if (!string.IsNullOrWhiteSpace(Location)) values["location"] = Location!;
        if (!string.IsNullOrWhiteSpace(CoCd)) values["cocd"] = CoCd!;
        if (DivCd.HasValue) values["divcd"] = DivCd.Value.ToString();
        if (LocCd.HasValue) values["loccd"] = LocCd.Value.ToString();
        if (!string.IsNullOrWhiteSpace(Ref)) values["ref"] = Ref!;
        return values;
    }
}
