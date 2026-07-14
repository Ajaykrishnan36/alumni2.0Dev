global class KenLinkedInRegistrationHandler implements Auth.RegistrationHandler {

    global User createUser(Id portalId, Auth.UserData data) {

        List<User> users = [
            SELECT Id,Email
            FROM User
            WHERE Email =:data.Email
            AND Profile.Name = 'Alumni-Student'
            AND IsActive = true
            LIMIT 1
        ];

        if (users.isEmpty()) {
            throw new SObjectException('No active user found. Please register first.');
        }

        return users[0];
    }

    global void updateUser(Id userId, Id portalId, Auth.UserData data) {
        User u = new User(Id = userId);
        update u;
    }
}