package desk_companion_backend.auth.google;

public interface GoogleTokenVerifier {

    GoogleTokenPayload verify(String idToken);
}