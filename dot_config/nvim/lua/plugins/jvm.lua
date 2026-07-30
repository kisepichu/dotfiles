-- Kotlin / Java(Spring Boot) 開発環境の追加設定。
-- LSP / treesitter / dap / ktlint の本体は LazyVim の extras
-- (lang.java, lang.kotlin) が入れているので、ここでは Spring Boot のみ補う。
return {
  -- Spring Boot Language Server + jdtls 拡張 jar を mason で導入。
  -- spring-boot.nvim はこのパッケージから LS 本体と jdtls bundles を探す。
  {
    "mason-org/mason.nvim",
    opts = { ensure_installed = { "vscode-spring-boot-tools" } },
  },

  -- Spring Boot サポート。java/yaml/properties で起動し、
  -- application.yml / properties 補完や Spring シンボルナビを提供する。
  {
    "JavaHello/spring-boot.nvim",
    ft = { "java", "yaml", "jproperties" },
    dependencies = { "mfussenegger/nvim-jdtls" },
    opts = {},
  },

  -- LazyVim の java extra が組む jdtls 設定に Spring Boot の拡張 bundle を注入する。
  -- java.lua は最終的に extend_or_override(config, opts.jdtls) を呼ぶので、
  -- opts.jdtls を関数にしておくと init_options.bundles を後付けできる。
  {
    "mfussenegger/nvim-jdtls",
    optional = true,
    opts = function(_, opts)
      opts.jdtls = function(config)
        config.init_options = config.init_options or {}
        config.init_options.bundles = config.init_options.bundles or {}
        vim.list_extend(config.init_options.bundles, require("spring_boot").java_extensions())
        return config
      end
    end,
  },
}
