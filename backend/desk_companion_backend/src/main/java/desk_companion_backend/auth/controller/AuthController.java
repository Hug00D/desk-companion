package desk_companion_backend.auth.controller;

import desk_companion_backend.auth.dto.AuthResponse;
import desk_companion_backend.auth.dto.LoginRequest;
import desk_companion_backend.auth.service.AuthService;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v1/auth")
public class AuthController {

    private final AuthService authService;

    public AuthController(AuthService authService) {
        this.authService = authService;
    }

    @PostMapping("/login")
    public AuthResponse login(@Valid @RequestBody LoginRequest request) {
        return authService.login(request);
    }
}