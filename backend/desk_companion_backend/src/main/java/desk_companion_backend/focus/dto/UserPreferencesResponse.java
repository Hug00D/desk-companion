package desk_companion_backend.focus.dto;

import java.util.UUID;

public record UserPreferencesResponse(
        UUID userId,
        boolean quietMode,
        String reminderSensitivity,
        String aiResponseTone,
        String timezone,
        boolean syncEnabled,
        boolean storeTranscript,
        boolean storeDebugSnapshot,
        int schemaVersion
) {
}
