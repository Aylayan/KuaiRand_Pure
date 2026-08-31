-- ============================================================
-- KuaiRand-Pure：创建项目数据库
-- 执行环境：MySQL（建议在 DBeaver 的 SQL 编辑器中执行）
-- 本脚本不会删除或覆盖已有数据库。
-- ============================================================

CREATE DATABASE IF NOT EXISTS `kuairand_analytics`
    CHARACTER SET utf8mb4             #设置默认字符集为 utf8mb4。可以安全保存中文、英文、符号和emoji。
    COLLATE utf8mb4_unicode_ci;       #指定文本的排序和比较规则。unicode 表示按照Unicode规则比较字符。ci 是 case-insensitive，表示英文字母比较时通常不区分大小写。

USE `kuairand_analytics`;

-- 用于确认当前连接已经切换到项目数据库。
SELECT DATABASE() AS `current_database`;
