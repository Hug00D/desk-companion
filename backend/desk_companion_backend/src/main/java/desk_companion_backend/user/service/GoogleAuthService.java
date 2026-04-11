package desk_companion_backend.user.service;

import desk_companion_backend.auth.dto.GoogleLoginResponse;

public interface GoogleAuthService {

    GoogleLoginResponse loginOrRegister(String idToken);
}