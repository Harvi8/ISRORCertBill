using ISRORBilling;
using ISRORUnified.Infrastructure.ServiceRegistration;

var builder = WebApplication.CreateBuilder(args);

builder.Configuration.ValidateUnifiedConfiguration();
builder.Services.AddUnifiedLogging(builder.Configuration);
builder.Services.AddBilling(builder.Configuration);
builder.Services.AddCertification(builder.Configuration);

var app = builder.Build();

app.MapBillingEndpoints();
app.MapHealthEndpoints();
app.UseMiddleware<GenericHandlerMiddleware>();

app.Run();
