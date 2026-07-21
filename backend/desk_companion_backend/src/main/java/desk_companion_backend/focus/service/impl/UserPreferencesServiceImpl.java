package desk_companion_backend.focus.service.impl;

import desk_companion_backend.common.exception.UserNotFoundException;
import desk_companion_backend.focus.dto.UserPreferencesRequest;
import desk_companion_backend.focus.dto.UserPreferencesResponse;
import desk_companion_backend.focus.entity.UserPreferences;
import desk_companion_backend.focus.repository.UserPreferencesRepository;
import desk_companion_backend.focus.service.UserPreferencesService;
import desk_companion_backend.user.entity.User;
import desk_companion_backend.user.repository.UserRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.UUID;

@Service
@Transactional(readOnly = true)
public class UserPreferencesServiceImpl implements UserPreferencesService {

    private final UserRepository userRepository;
    private final UserPreferencesRepository userPreferencesRepository;

    public UserPreferencesServiceImpl(
            UserRepository userRepository,
            UserPreferencesRepository userPreferencesRepository
    ) {
        this.userRepository = userRepository;
        this.userPreferencesRepository = userPreferencesRepository;
    }

    @Override
    @Transactional
    public UserPreferencesResponse getPreferences(UUID userId) {
        UserPreferences preferences = userPreferencesRepository.findById(userId)
                .orElseGet(() -> createDefaultPreferences(getUser(userId)));
        return toResponse(preferences);
    }

    @Override
    @Transactional
    public UserPreferencesResponse updatePreferences(UUID userId, UserPreferencesRequest request) {
        User user = getUser(userId);
        UserPreferences preferences = userPreferencesRepository.findById(userId)
                .orElseGet(() -> createDefaultPreferences(user));

        preferences.setQuietMode(request.quietMode());
        preferences.setReminderSensitivity(request.reminderSensitivity().trim());
        preferences.setAiResponseTone(request.aiResponseTone().trim());
        preferences.setTimezone(request.timezone().trim());
        preferences.setSyncEnabled(request.syncEnabled());
        preferences.setStoreTranscript(request.storeTranscript());
        preferences.setStoreDebugSnapshot(request.storeDebugSnapshot());
        preferences.setSchemaVersion(request.schemaVersion() == null ? 1 : request.schemaVersion());

        return toResponse(userPreferencesRepository.save(preferences));
    }

    private UserPreferences createDefaultPreferences(User user) {
        UserPreferences preferences = new UserPreferences();
        preferences.setUser(user);
        return userPreferencesRepository.save(preferences);
    }

    private User getUser(UUID userId) {
        return userRepository.findById(userId)
                .orElseThrow(UserNotFoundException::new);
    }

    private UserPreferencesResponse toResponse(UserPreferences preferences) {
        return new UserPreferencesResponse(
                preferences.getUserId(),
                preferences.isQuietMode(),
                preferences.getReminderSensitivity(),
                preferences.getAiResponseTone(),
                preferences.getTimezone(),
                preferences.isSyncEnabled(),
                preferences.isStoreTranscript(),
                preferences.isStoreDebugSnapshot(),
                preferences.getSchemaVersion()
        );
    }
}
