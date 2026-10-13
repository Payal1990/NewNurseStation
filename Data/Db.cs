using System.Data;
using System.Globalization;
using Microsoft.Data.SqlClient;

namespace NurseStationTablet.Data;

/// <summary>
/// Minimal ADO.NET helper that replaces SofCommon.DBFactory/DBRequest from the WCF service.
/// Parameters are passed with the same names the WCF DAL used (SqlClient adds the "@").
/// </summary>
public sealed class Db
{
    private readonly string _connectionString;

    public Db(IConfiguration config)
    {
        _connectionString = config.GetConnectionString("CareWorks")
            ?? throw new InvalidOperationException("ConnectionStrings:CareWorks is not configured.");
    }

    public SqlConnection Open()
    {
        var cn = new SqlConnection(_connectionString);
        cn.Open();
        return cn;
    }

    public static SqlCommand Proc(SqlConnection cn, string name, params (string Name, object? Value)[] args) =>
        Build(cn, null, name, CommandType.StoredProcedure, args);

    public static SqlCommand Proc(SqlConnection cn, SqlTransaction tx, string name, params (string Name, object? Value)[] args) =>
        Build(cn, tx, name, CommandType.StoredProcedure, args);

    private static SqlCommand Build(SqlConnection cn, SqlTransaction? tx, string text, CommandType type, (string Name, object? Value)[] args)
    {
        var cmd = new SqlCommand(text, cn, tx) { CommandType = type, CommandTimeout = 120 };
        foreach (var (name, value) in args)
            cmd.Parameters.AddWithValue(name.StartsWith('@') ? name : "@" + name, value ?? DBNull.Value);
        return cmd;
    }

    /// <summary>Runs a procedure and maps every row of the first result set.</summary>
    public List<T> List<T>(string proc, Func<Row, T> map, params (string, object?)[] args)
    {
        using var cn = Open();
        using var cmd = Proc(cn, proc, args);
        using var rd = cmd.ExecuteReader();
        var row = new Row(rd);
        var list = new List<T>();
        while (rd.Read()) list.Add(map(row));
        return list;
    }

    /// <summary>Runs a parameterised inline SQL query (CommandType.Text) and maps every row of the first result set.</summary>
    public List<T> TextList<T>(string sql, Func<Row, T> map, params (string, object?)[] args)
    {
        using var cn = Open();
        using var cmd = new SqlCommand(sql, cn) { CommandType = CommandType.Text, CommandTimeout = 120 };
        foreach (var (name, value) in args)
            cmd.Parameters.AddWithValue(name.StartsWith('@') ? name : "@" + name, value ?? DBNull.Value);
        using var rd = cmd.ExecuteReader();
        var row = new Row(rd);
        var list = new List<T>();
        while (rd.Read()) list.Add(map(row));
        return list;
    }

    /// <summary>Legacy DAL pattern: read all rows, keep the last one (While dr.Read ... obj = ...).</summary>
    public T? Last<T>(string proc, Func<Row, T> map, params (string, object?)[] args) where T : class
    {
        T? last = null;
        foreach (var item in List(proc, map, args)) last = item;
        return last;
    }

    public object? Scalar(string proc, params (string, object?)[] args)
    {
        using var cn = Open();
        using var cmd = Proc(cn, proc, args);
        var v = cmd.ExecuteScalar();
        return v is DBNull ? null : v;
    }

    public int NonQuery(string proc, params (string, object?)[] args)
    {
        using var cn = Open();
        using var cmd = Proc(cn, proc, args);
        return cmd.ExecuteNonQuery();
    }

    /// <summary>Typed, null-safe access to the current reader row by column name (IIf(IsDBNull(...)) in the DAL).</summary>
    public sealed class Row
    {
        private readonly SqlDataReader _rd;
        private Dictionary<string, int>? _ordinals;

        public Row(SqlDataReader rd) => _rd = rd;

        public bool Has(string column)
        {
            _ordinals ??= Enumerable.Range(0, _rd.FieldCount).ToDictionary(_rd.GetName, i => i, StringComparer.OrdinalIgnoreCase);
            return _ordinals.ContainsKey(column);
        }

        public object? Raw(string column)
        {
            if (!Has(column)) return null;
            var v = _rd.GetValue(_ordinals![column]);
            return v is DBNull ? null : v;
        }

        public string Str(string column, string fallback = "") => Raw(column) is { } v ? Convert.ToString(v, CultureInfo.InvariantCulture) ?? fallback : fallback;
        public int Int(string column, int fallback = 0) => Raw(column) is { } v ? Convert.ToInt32(v, CultureInfo.InvariantCulture) : fallback;
        public long Long(string column, long fallback = 0) => Raw(column) is { } v ? Convert.ToInt64(v, CultureInfo.InvariantCulture) : fallback;
        public decimal Dec(string column) => Raw(column) is { } v ? Convert.ToDecimal(v, CultureInfo.InvariantCulture) : 0m;
        public DateTime Date(string column) => Raw(column) is { } v ? Convert.ToDateTime(v, CultureInfo.InvariantCulture) : default;

        /// <summary>VB-style CBool: bits, numbers, "True"/"False", "Y"/"N", "1"/"0".</summary>
        public bool Bool(string column)
        {
            var v = Raw(column);
            return v switch
            {
                null => false,
                bool b => b,
                string s => s.Trim() is var t && (t.Equals("true", StringComparison.OrdinalIgnoreCase) || t == "1" || t.Equals("Y", StringComparison.OrdinalIgnoreCase)),
                _ => Convert.ToDecimal(v, CultureInfo.InvariantCulture) != 0,
            };
        }

        /// <summary>First column of the row (DataSet.Tables(0).Rows(0)(0) in the DAL).</summary>
        public object? First() => _rd.FieldCount == 0 || _rd.IsDBNull(0) ? null : _rd.GetValue(0);
    }
}
