package desk_companion_backend.focus.controller;

import desk_companion_backend.focus.dto.UserPreferencesRequest;
import desk_companion_backend.focus.dto.UserPreferencesResponse;
import desk_companion_backend.focus.service.UserPreferencesService;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.UUID;

@RestController
@RequestMapping("/api/v1/users/{userId}/preferences")
public class UserPreferencesController {

    private final UserPreferencesService userPreferencesService;

    public UserPreferencesController(UserPreferencesService userPreferencesService) {
        this.userPreferencesService = userPreferencesService;
    }

    @GetMapping
    public UserPreferencesResponse getPreferences(@PathVariable UUID userId) {
        return userPreferencesService.getPreferences(userId);
    }

    @PutMapping
    public UserPreferencesResponse updatePreferences(
            @PathVariable UUID userId,
            @Valid @RequestBody UserPreferencesRequest request
    ) {
        return userPreferencesService.updatePreferences(userId, request);
    }
}
