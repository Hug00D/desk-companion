package desk_companion_backend.auth.service;

import desk_companion_backend.auth.dto.AuthResponse;
import desk_companion_backend.auth.dto.LoginRequest;

public interface AuthService {
    AuthResponse login(LoginRequest request);
}