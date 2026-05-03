module.exports = {
  apps: [{
    name: "vibelinx-api",
    script: "./dist/server.js",
    instances: 1,
    exec_mode: "fork",
    watch: false,
    max_memory_restart: "600M",
    env_production: {
      NODE_ENV: "production",
      PORT: 3001
    },
    // Logging settings
    log_date_format: "YYYY-MM-DD HH:mm Z",
    error_file: "./logs/pm2-error.log",
    out_file: "./logs/pm2-out.log",
    merge_logs: true,
    autorestart: true,
    restart_delay: 4000, // Wait 4 seconds before restarting if it crashes
  }]
}
