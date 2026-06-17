using ISRORBilling.Database;
using ISRORBilling.Models.Authentication;
using ISRORBilling.Models.Notification;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;

namespace ISRORBilling.Services.Notification.CommunityProvided;

/// <summary>
/// You need to create the stored procedure Update_ItemLock, which can be found under Database->CommunityProvided->F3rreNotificationService
/// </summary>
public class FerreNotificationService : INotificationService
{
    private readonly AccountContext _accountContext;
    private readonly ILogger<FerreNotificationService> _logger;

    public FerreNotificationService(AccountContext accountContext, ILogger<FerreNotificationService> logger)
    {
        _accountContext = accountContext;
        _logger = logger;
    }
    
    private int UpdateLockPw(int jid, string email, string lockPw) =>
        _accountContext.Database
            .SqlQueryRaw<int?>(
                "EXEC Update_ItemLock @jid = @JID, @email = @Email, @lockPw = @LockPw",
                new SqlParameter("@JID", jid),
                new SqlParameter("@Email", email),
                new SqlParameter("@LockPw", lockPw))
            .AsEnumerable().FirstOrDefault() ?? -1;

    private int UpdatesecondaryPw(int jid, string email, string secPassWord) =>
        _accountContext.Database
            .SqlQueryRaw<int?>(
                "EXEC Update_SecPassWord @jid = @JID, @email = @Email, @SecPassWord = @SecPassWord",
                new SqlParameter("@JID", jid),
                new SqlParameter("@Email", email),
                new SqlParameter("@SecPassWord", secPassWord))
            .AsEnumerable().FirstOrDefault() ?? -1;

    public Task<bool> SendSecondPassword(SendCodeRequest request)
    {
        if (!request.Validate())
        {
            _logger.LogCritical("Couldn't validate if request was legitimate. Ensure the SaltKey matches the one in GatewayServer. [Error Code: {ErrorCode}]\nDetails:{Request}", (int)LoginResponseCodeEnum.Emergency, request);
            return Task.FromResult(false);
        }
        
        if (UpdatesecondaryPw(request.jid, request.email, request.code) >= 0)
            return Task.FromResult(true);

        _logger.LogError("Sending second password by email has Failed for [{StrEmail}]", request.email);
        return Task.FromResult(false);
    }

    public Task<bool> SendItemLockCode(SendCodeRequest request)
    {
        if (!request.Validate())
        {
            _logger.LogCritical("Couldn't validate if request was legitimate. Ensure the SaltKey matches the one in GatewayServer. [Error Code: {ErrorCode}]\nDetails:{Request}", (int)LoginResponseCodeEnum.Emergency, request);
            return Task.FromResult(false);
        }

        if(UpdateLockPw(request.jid, request.email, request.code) >= 0) 
            return Task.FromResult(true);
        
        _logger.LogError("Sending Item Lock Key has failed for [{RequestEmail}]", request.email);
        return Task.FromResult(false);
    }
    
    
}
