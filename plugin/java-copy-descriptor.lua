if vim.g.loaded_java_copy_descriptor then
  return
end
vim.g.loaded_java_copy_descriptor = 1

vim.api.nvim_create_user_command('JavaCopyDescriptor', function()
  require('java-copy-descriptor').copy()
end, {
  desc = 'Copy the JVM descriptor of the Java method under the cursor',
  force = false,
})
