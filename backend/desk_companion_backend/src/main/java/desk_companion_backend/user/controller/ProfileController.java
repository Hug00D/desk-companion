package desk_companion_backend.user.controller;

import desk_companion_backend.user.dto.ProfileResponse;
import desk_companion_backend.user.dto.UpdateProfileRequest;
import desk_companion_backend.user.service.ProfileService;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.*;

import java.util.UUID;

@RestController
@RequestMapping("/api/v1/users/{userId}/profile")
public class ProfileController {

    private final ProfileService profileService;

    public ProfileController(ProfileService profileService) {
        this.profileService = profileService;
    }

    // 查詢 profile：GET 不需要 RequestBody
    @GetMapping
    public ProfileResponse getProfile(@PathVariable UUID userId) {
        return profileService.getProfile(userId);
    }

    // 更新 profile：才需要 UpdateProfileRequest
    @PutMapping
    public ProfileResponse updateProfile(
            @PathVariable UUID userId,
            @Valid @RequestBody UpdateProfileRequest request
    ) {
        return profileService.updateProfile(userId, request);
    }
}