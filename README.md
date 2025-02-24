# freshrss

# Build
```
dset freshrss

####### ./run
cat <<EOF | tee docker-compose.yml >/dev/null
services:
    freshrss:
        image: superkeyor/freshrss
        container_name: freshrss
        ports:
            - 1030:80
        restart: unless-stopped
        volumes:
            - /data/freshrss/data:/var/www/FreshRSS/data
            # - /data/freshrss/extensions:/var/www/FreshRSS/extensions
        environment:
            TZ: "US/Central"
            CRON_MIN: "3,33"
            TRUSTED_PROXY: 172.16.0.1/12 192.168.0.1/16
EOF
cat <<EOF | tee run >/dev/null
docker compose down
docker pull superkeyor/freshrss
docker compose up
EOF
chmod +x run
```
