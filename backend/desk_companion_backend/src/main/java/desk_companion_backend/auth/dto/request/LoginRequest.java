package desk_companion_backend.auth.dto;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record LoginRequest(
        @NotBlank(message = "Email 不能為空")
        @Email(message = "Email 格式不正確")
        String email,

        @NotBlank(message = "密碼不能為空")
        @Size(min = 8, max = 100, message = "密碼長度需在 8-100 之間")
        String password 
) {}