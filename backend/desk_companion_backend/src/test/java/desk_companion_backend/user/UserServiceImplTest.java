package desk_companion_backend.user;

import desk_companion_backend.common.exception.InvalidCredentialsException;
import desk_companion_backend.user.entity.AccountStatus;
import desk_companion_backend.user.entity.User;
import desk_companion_backend.user.mapper.UserMapper;
import desk_companion_backend.user.repository.UserRepository;
import desk_companion_backend.user.service.ProfileService;
import desk_companion_backend.user.service.impl.UserServiceImpl;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.security.crypto.password.PasswordEncoder;

import java.util.Optional;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class UserServiceImplTest {

    private UserRepository userRepository;
    private PasswordEncoder passwordEncoder;
    private UserServiceImpl service;

    @BeforeEach
    void setUp() {
        userRepository = mock(UserRepository.class);
        passwordEncoder = mock(PasswordEncoder.class);
        service = new UserServiceImpl(
                userRepository,
                mock(ProfileService.class),
                mock(UserMapper.class),
                passwordEncoder
        );
    }

    @Test
    void softDeleteRequiresCorrectPassword() {
        User user = activeUser();
        when(userRepository.findById(user.getId())).thenReturn(Optional.of(user));
        when(passwordEncoder.matches("WrongPass1!", user.getPasswordHash())).thenReturn(false);

        assertThrows(
                InvalidCredentialsException.class,
                () -> service.softDelete(user.getId(), "WrongPass1!")
        );
        assertEquals(AccountStatus.ACTIVE, user.getAccountStatus());

        when(passwordEncoder.matches("Password123!", user.getPasswordHash())).thenReturn(true);
        service.softDelete(user.getId(), "Password123!");
        assertEquals(AccountStatus.DELETED, user.getAccountStatus());
    }

    private User activeUser() {
        User user = new User();
        user.setId(UUID.randomUUID());
        user.setEmail("test@gmail.com");
        user.setPasswordHash("stored-hash");
        user.setAccountStatus(AccountStatus.ACTIVE);
        return user;
    }
}
