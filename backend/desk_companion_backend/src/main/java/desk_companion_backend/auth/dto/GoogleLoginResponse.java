package desk_companion_backend.auth.dto;

import desk_companion_backend.user.dto.UserResponse;

public record GoogleLoginResponse(
        boolean isNewUser,
        UserResponse user
) {}