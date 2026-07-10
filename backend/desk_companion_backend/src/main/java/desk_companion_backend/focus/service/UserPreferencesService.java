package desk_companion_backend.focus.service;

import desk_companion_backend.focus.dto.UserPreferencesRequest;
import desk_companion_backend.focus.dto.UserPreferencesResponse;

import java.util.UUID;

public interface UserPreferencesService {

    UserPreferencesResponse getPreferences(UUID userId);

    UserPreferencesResponse updatePreferences(UUID userId, UserPreferencesRequest request);
}
