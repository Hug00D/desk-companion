package desk_companion_backend.user.service;

import desk_companion_backend.user.dto.AccountStatusCheckResponse;
import desk_companion_backend.user.dto.RegisterUserRequest;
import desk_companion_backend.user.dto.UserResponse;
import desk_companion_backend.user.entity.User;

import java.util.UUID;

public interface UserService {

    UserResponse register(RegisterUserRequest request);

    UserResponse getById(UUID userId);

    UserResponse getByEmail(String email);

    void softDelete(UUID userId);

    void assertLoginAllowed(User user);

    AccountStatusCheckResponse checkAccountStatus(UUID userId);
}