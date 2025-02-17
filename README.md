# freshrss

# Build
```
####### global settings
IMAGE_NAME="freshrss"

####### git clone
cp ~/Desktop/Dropbox/Apps/Git/config/.ssh/id_ed25519 ~/.ssh/id_ed25519
cp ~/Desktop/Dropbox/Apps/Git/config/.gitconfig ~/.gitconfig
cd ~/Desktop
git clone git@github.com:/superkeyor/${IMAGE_NAME}.git
cd ${IMAGE_NAME}

####### ./run
cat <<EOF | tee docker-compose.yml >/dev/null
services:
    freshrss:
        image: freshrss
        container_name: superkeyor/freshrss
        ports:
            - 1030:80
        restart: unless-stopped
        volumes:
            - /data/freshrss/data:/var/www/FreshRSS/data
            - /data/freshrss/extensions:/var/www/FreshRSS/extensions
        environment:
            TZ: "US/Central"
            CRON_MIN: "3,33"
            TRUSTED_PROXY: 172.16.0.1/12 192.168.0.1/16
EOF
cat <<EOF | tee run >/dev/null
docker compose down
docker compose up
EOF
chmod +x run

####### docker hub
IMAGE_NAME=$(basename $(pwd))
echo "Docker Hub Password (formula): "
sudo docker login -u superkeyor

####### upload to github and dockerhub
cat <<EOF | tee upload >/dev/null
#!/usr/bin/env bash
csd="\$( cd "\$( dirname "\${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "\$csd"

# git config --global --add safe.directory .
# git reset --hard   # discard local changes
# git pull git@github.com:/superkeyor/${IMAGE_NAME}.git

git add -A 
git commit -m 'update'
git push git@github.com:/superkeyor/${IMAGE_NAME}.git

if [[ $(command -v docker) != "" ]]; then
sudo docker build -t ${IMAGE_NAME} .
sudo docker image tag ${IMAGE_NAME} superkeyor/${IMAGE_NAME}:latest
sudo docker image push superkeyor/${IMAGE_NAME}:latest
fi
EOF
chmod +x upload   # ./upload
```
