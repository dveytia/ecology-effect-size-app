
result    <- sb_auth_login("deviveytia@hotmail.com", "Alphie1851")
my_token  <- result$access_token
my_user_id <- result$user$id

sb_post("projects",
  list(owner_id    = my_user_id,
       title       = "Diagnostic test",
       description = "403 debug"),
  token = my_token)

source("R/utils.R"); source("R/supabase.R"); readRenviron(".Renviron")
a <- sb_auth_login("deviveytia@hotmail.com", "Alphie1851")
sb_post("projects", list(owner_id = a$user$id, title = "TEST"), token = a$access_token)
sb_delete("projects", "project_id", "ad1a5301-40f1-40e6-ac8a-75e94d9f1fbd", token = SVC_KEY)

shiny::runApp("c:/Users/deviv/R-working-folder/ecology-effect-size-app", launch.browser = TRUE)
