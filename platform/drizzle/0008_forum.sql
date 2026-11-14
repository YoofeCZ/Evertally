-- Forum: threads and posts shared by the website and the in-game Community page.
-- The opening post of a thread is a post whose id equals the thread id. Author is the full character name "Name-Realm".
-- Deleting is soft (deleted_at) so a post that the addon already holds can still be recognised as gone.
CREATE TABLE IF NOT EXISTS et_forum_threads (
  id TEXT PRIMARY KEY NOT NULL,
  category TEXT NOT NULL,
  title TEXT NOT NULL,
  user_id TEXT NOT NULL,
  author TEXT NOT NULL,
  class_id INTEGER,
  origin TEXT NOT NULL,
  pinned INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  last_post_at INTEGER NOT NULL,
  reply_count INTEGER NOT NULL DEFAULT 0,
  deleted_at INTEGER
);
CREATE INDEX IF NOT EXISTS forum_threads_listing ON et_forum_threads(category, deleted_at, last_post_at);
CREATE INDEX IF NOT EXISTS forum_threads_user ON et_forum_threads(user_id);
CREATE TABLE IF NOT EXISTS et_forum_posts (
  id TEXT PRIMARY KEY NOT NULL,
  thread_id TEXT NOT NULL,
  reply_to TEXT,
  user_id TEXT NOT NULL,
  author TEXT NOT NULL,
  class_id INTEGER,
  origin TEXT NOT NULL,
  body TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  deleted_at INTEGER
);
CREATE INDEX IF NOT EXISTS forum_posts_thread ON et_forum_posts(thread_id, created_at);
CREATE INDEX IF NOT EXISTS forum_posts_user ON et_forum_posts(user_id, created_at);
