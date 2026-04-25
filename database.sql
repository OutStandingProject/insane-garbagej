CREATE TABLE
    IF NOT EXISTS `0resmon_garbage_players` (
        id INT AUTO_INCREMENT PRIMARY KEY,
        identifier VARCHAR(255) NOT NULL,
        characterName VARCHAR(255) NOT NULL,
        exp INT DEFAULT 0,
        photo INT DEFAULT 7,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    );