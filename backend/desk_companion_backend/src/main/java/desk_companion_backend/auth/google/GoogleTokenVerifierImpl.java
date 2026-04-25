package desk_companion_backend.auth.google;

import desk_companion_backend.common.exception.InvalidGoogleTokenException;
import org.springframework.stereotype.Component;

@Component
public class GoogleTokenVerifierImpl implements GoogleTokenVerifier {

    @Override
    public GoogleTokenPayload verify(String idToken) {
        if (idToken == null || idToken.isBlank()) {
            throw new InvalidGoogleTokenException();
        }

        throw new UnsupportedOperationException("Google token verification is not implemented yet.");
    }
}