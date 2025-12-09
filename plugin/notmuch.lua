vim.api.nvim_create_user_command("Notmuch", function(arg) require("notmuch").command(arg.args) end, { nargs = "*" })

--TODO: move the commands below to be handled via a single Notmuch command
vim.cmd([[
  command -complete=custom,notmuch#CompSearchTerms -nargs=* NmSearch :call v:lua.require('notmuch').search_terms(<q-args>)
  command -complete=custom,notmuch#CompAddress -nargs=* ComposeMail :call v:lua.require('notmuch.send').compose(<q-args>)
]])
