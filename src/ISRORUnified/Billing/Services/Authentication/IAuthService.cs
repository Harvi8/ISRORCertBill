using ISRORBilling.Models.Authentication;

namespace ISRORBilling.Services.Authentication;

public interface IAuthService
{
    AUserLoginResponse Login(string userId, string userPw, string channel) =>
        throw new NotSupportedException("This authentication service requires a complete gateway request.");

    AUserLoginResponse Login(CheckUserRequest request) =>
        Login(request.UserId, request.HashedUserPassword, request.ChannelId.ToString());
}
