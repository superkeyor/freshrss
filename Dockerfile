# https://github.com/FreshRSS/FreshRSS/blob/latest/Docker/Dockerfile
# https://hub.docker.com/r/freshrss/freshrss/tags
FROM freshrss/freshrss:1.27.1

ENV TZ=UTC
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Install required packages
RUN apt-get update && apt-get install -y \
    git \
    unzip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /var/www/FreshRSS

# ArticleSummary extension https://github.com/LiangWei88/xExtension-ArticleSummary
RUN git clone https://github.com/superkeyor/xExtension-ArticleSummary.git && \
    cp -r xExtension-ArticleSummary ./extensions && \
    rm -rf xExtension-ArticleSummary

# ReadingTime extension
RUN git clone https://github.com/superkeyor/FreshRSS_Extension-ReadingTime.git && \
    cp -r FreshRSS_Extension-ReadingTime ./extensions && \
    rm -rf FreshRSS_Extension-ReadingTime

# FilterTitle extension
RUN git clone https://github.com/superkeyor/cntools_FreshRssExtensions.git && \
    cp -r cntools_FreshRssExtensions/xExtension-FilterTitle ./extensions && \
    rm -rf cntools_FreshRssExtensions

# MarkPreviousAsRead extension
RUN git clone https://github.com/kalvn/freshrss-mark-previous-as-read.git && \
    cp -r freshrss-mark-previous-as-read/xExtension-MarkPreviousAsRead ./extensions && \
    rm -rf freshrss-mark-previous-as-read
    
# TitleWrap etc extension
RUN git clone https://github.com/FreshRSS/Extensions.git && \
    cp -r Extensions/xExtension-TitleWrap ./extensions && \
    cp -r Extensions/xExtension-showFeedID ./extensions && \
    rm -rf Extensions

# Set permissions
RUN chown -R www-data:www-data /var/www/FreshRSS/extensions && \
    chmod -R 755 /var/www/FreshRSS/extensions && \
    chown www-data:www-data /var/www/FreshRSS/p/scripts/main.js

# Use default FreshRSS entrypoint
ENV COPY_LOG_TO_SYSLOG=On
ENV COPY_SYSLOG_TO_STDERR=On
ENV CRON_MIN=''
ENV DATA_PATH=''
ENV FRESHRSS_ENV=''
ENV LISTEN=''
ENV OIDC_ENABLED=''
ENV TRUSTED_PROXY=''

ENTRYPOINT ["./Docker/entrypoint.sh"]

EXPOSE 80
# hadolint ignore=DL3025
CMD ([ -z "$CRON_MIN" ] || cron) && \
    . /etc/apache2/envvars && \
    exec apache2 -D FOREGROUND $([ -n "$OIDC_ENABLED" ] && [ "$OIDC_ENABLED" -ne 0 ] && echo '-D OIDC_ENABLED')
