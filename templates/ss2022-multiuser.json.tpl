{
  "log": {
    "disabled": false,
    "level": "info"
  },
  "inbounds": [
    {
      "type": "shadowsocks",
      "listen": "::",
      "listen_port": __SS_PORT__,
      "method": "2022-blake3-aes-256-gcm",
      "users": [
__USER_BLOCK__
      ],
      "network": "tcp,udp"
    }
  ],
  "outbounds": [
    {
      "type": "direct"
    }
  ]
}
