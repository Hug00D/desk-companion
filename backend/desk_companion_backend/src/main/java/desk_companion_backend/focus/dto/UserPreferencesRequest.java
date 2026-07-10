package desk_companion_backend.focus.dto;

import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

public record UserPreferencesRequest(
        @NotNull(message = "quietMode is required")
        Boolean quietMode,

        @NotBlank(message = "reminderSensitivity is required")
        String reminderSensitivity,

        @NotBlank(message = "aiResponseTone is required")
        String aiResponseTone,

        @NotBlank(message = "timezone is required")
        String timezone,

        @NotNull(message = "syncEnabled is required")
        Boolean syncEnabled,

        @NotNull(message = "storeTranscript is required")
        Boolean storeTranscript,

        @NotNull(message = "storeDebugSnapshot is required")
        Boolean storeDebugSnapshot,

        @Min(value = 1, message = "schemaVersion must be positive")
        Integer schemaVersion
) {
}
