package desk_companion_backend.auth.google;

public record GoogleTokenPayload(
        String sub,
        String email,
        boolean emailVerified
) {
}