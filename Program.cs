using NurseStationTablet.Infrastructure;
using NurseStationTablet.Data;
using NurseStationTablet.Services;

var builder = WebApplication.CreateBuilder(args);

// One address to change per environment: Legacy:BaseUrl. Every legacy / EMR address is derived from it.
// A key that is set explicitly (appsettings or environment) still overrides its derived value.
{
    var cfg = builder.Configuration;
    var root = (cfg["Legacy:BaseUrl"] ?? "").Trim().TrimEnd('/');
    if (root.Length > 0)
    {
        string Site(string key, string fallback) => (cfg["Legacy:" + key] ?? fallback).Trim().Trim('/');
        var appSite = Site("AppSite", "CLIENTR2");
        ((IConfigurationBuilder)cfg).Sources.Insert(0, new Microsoft.Extensions.Configuration.Memory.MemoryConfigurationSource
        {
            InitialData = new Dictionary<string, string?>
            {
                ["Legacy:BaseAppPath"] = $"{root}/{appSite}/",
                ["Legacy:BaseMvcAppPath"] = $"{root}/{Site("MvcSite", "CWWEBMVC")}/",
                ["Legacy:AngularEMRPath"] = $"{root}/{Site("EmrSite", "EMR_App")}",
                ["Legacy:EmrV2Path"] = $"{root}/{Site("EmrV2Site", "EMR_AppV2")}",
                ["Legacy:SubMenuPath"] = $"{root}/{appSite}/MainLoginAsp/Pages/Dashboard.aspx",
                ["Legacy:LoginPath"] = $"{root}/{appSite}/MainLoginAsp/Pages/Login.aspx",
                ["Legacy:ClientImg"] = $"{root}/{appSite}/Images/SofPro.ico",
                ["Legacy:SofImg"] = $"{root}/{appSite}/Images/yellow.jpg",
            },
        });
    }
}

builder.Services.AddDistributedMemoryCache();
builder.Services.AddSession(o =>
{
    o.Cookie.Name = ".NurseStationTablet";
    o.Cookie.HttpOnly = true;
    o.Cookie.IsEssential = true;
    o.IdleTimeout = TimeSpan.FromMinutes(60);
});
builder.Services.AddSingleton<LegacySessionDecoder>();
builder.Services.AddSingleton<Db>();
builder.Services.AddSingleton<SmsComposer>();
builder.Services.AddSingleton<NsRepository>();
builder.Services.AddMemoryCache();
builder.Services.AddSingleton<LegacyEmrBridge>();
builder.Services.AddSingleton<SimplifiedModuleLauncher>();
builder.Services.AddSingleton<LosService>();

// Razor Pages serve the UI (Pages/Index); the JSON API is kept as Minimal-API endpoints (not MVC).
builder.Services.AddRazorPages();

var app = builder.Build();

if (!app.Environment.IsDevelopment()) app.UseExceptionHandler("/Error");

app.UseStaticFiles(new StaticFileOptions
{
    OnPrepareResponse = ctx => ctx.Context.Response.Headers["Cache-Control"] = "no-cache"
});

app.UseRouting();
app.UseSession();

// UI: Pages/Index.cshtml handles "/", the ref decode and the dev-session bootstrap in its OnGet.
app.MapRazorPages();

// JSON endpoints behind the page (/api/ns/*). Minimal API, same as the original.
app.MapNurseStationApi();

app.Run();
