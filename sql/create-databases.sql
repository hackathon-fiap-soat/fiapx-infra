-- =============================================================================
-- FIAP X: criação dos databases e dos usuários de aplicação (MySQL 8.0 / Aurora MySQL 3)
--
-- Um database por serviço (ADR-005). Cada serviço tem o próprio usuário, com acesso só ao próprio
-- database. As tabelas são criadas pelas migrations de cada serviço, não por este script.
--
-- As senhas NÃO ficam neste arquivo. Antes de rodá-lo, defina as variáveis de sessão:
--   SET @fiapx_auth_password  = '...';
--   SET @fiapx_video_password = '...';
-- No ambiente local, isso é feito por local/init/mysql/01-create-databases.sh.
-- Na AWS, as senhas vêm do Secrets Manager.
--
-- O script é idempotente: pode ser executado mais de uma vez.
-- =============================================================================

CREATE DATABASE IF NOT EXISTS fiapx_auth  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
CREATE DATABASE IF NOT EXISTS fiapx_video CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

-- Falha cedo se alguma senha não foi definida.
SET @faltando = IF(@fiapx_auth_password IS NULL OR @fiapx_auth_password = ''
                   OR @fiapx_video_password IS NULL OR @fiapx_video_password = '',
                   'defina @fiapx_auth_password e @fiapx_video_password antes de rodar este script', NULL);
SET @sql = IF(@faltando IS NULL, 'DO 0', CONCAT('SIGNAL SQLSTATE ''45000'' SET MESSAGE_TEXT = ''', @faltando, ''''));
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- CREATE USER não aceita variável na senha, por isso as instruções são montadas e preparadas.
SET @sql = CONCAT('CREATE USER IF NOT EXISTS ''fiapx_auth''@''%'' IDENTIFIED BY ', QUOTE(@fiapx_auth_password));
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
SET @sql = CONCAT('ALTER USER ''fiapx_auth''@''%'' IDENTIFIED BY ', QUOTE(@fiapx_auth_password));
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @sql = CONCAT('CREATE USER IF NOT EXISTS ''fiapx_video''@''%'' IDENTIFIED BY ', QUOTE(@fiapx_video_password));
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
SET @sql = CONCAT('ALTER USER ''fiapx_video''@''%'' IDENTIFIED BY ', QUOTE(@fiapx_video_password));
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @sql = NULL;

-- Privilégios: DML para a aplicação e DDL para as migrations, só no próprio database.
-- Nenhum usuário de aplicação tem privilégio global nem acesso ao database do outro serviço.
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, INDEX, REFERENCES, DROP
  ON fiapx_auth.*  TO 'fiapx_auth'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, INDEX, REFERENCES, DROP
  ON fiapx_video.* TO 'fiapx_video'@'%';

FLUSH PRIVILEGES;
