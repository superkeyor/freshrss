# https://github.com/FreshRSS/FreshRSS/blob/latest/Docker/Dockerfile
# https://hub.docker.com/r/freshrss/freshrss/tags
FROM freshrss/freshrss:1.25.0

ENV TZ=UTC
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Install required packages
RUN apt-get update && apt-get install -y \
    git \
    unzip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /var/www/FreshRSS

# Not use; somehow not working well...
# # FilterTitle extension
# RUN git clone https://github.com/cn-tools/cntools_FreshRssExtensions.git && \
#     cp -r cntools_FreshRssExtensions/xExtension-FilterTitle ./extensions && \
#     rm -rf cntools_FreshRssExtensions
# # Patch FilterTitle extension
# # RUN sed -i "s/'blacklist' => array_filter(Minz_Request::paramTextToArray('blacklist', \[\])),/'blacklist' => array_filter(Minz_Request::paramTextToArray('blacklist', true)),/" ./extensions/xExtension-FilterTitle/extension.php && \
# #     sed -i "s/'whitelist' => array_filter(Minz_Request::paramTextToArray('whitelist', \[\])),/'whitelist' => array_filter(Minz_Request::paramTextToArray('whitelist', true)),/" ./extensions/xExtension-FilterTitle/extension.php && \
# #     sed -i '/private function isPatternFound(string $title, string $pattern): bool {/,/return false;/ { \
# #         s/if (1 === preg_match($pattern, $title))/if (1 === preg_match("\/$pattern\/u", $title))/ \
# #     }' ./extensions/xExtension-FilterTitle/extension.php
# COPY ./filter_extension.php ./extensions/xExtension-FilterTitle/extension.php

# TitleWrap extension
RUN git clone https://github.com/FreshRSS/Extensions.git && \
    cp -r Extensions/xExtension-TitleWrap ./extensions && \
    rm -rf Extensions

# ArticleSummary extension
RUN git clone https://github.com/LiangWei88/xExtension-ArticleSummary.git && \
    cp -r xExtension-ArticleSummary ./extensions && \
    rm -rf xExtension-ArticleSummary
# Patch ArticleSummary styling and functionality
COPY summary_script.js ./extensions/xExtension-ArticleSummary/static/script.js
RUN sed -i 's|background: #f8f8f8;|background: #6D6D6D; /* Medium gray background */\n  color: #FFFFFF; /* White font color for contrast */\n  border-radius: 10px; /* Rounded corners */|g' ./extensions/xExtension-ArticleSummary/static/style.css && \
    sed -i "s/target\.nextElementSibling\.querySelector('\.oai-summary-btn')\.innerHTML = 'Summarize'/target.nextElementSibling.querySelectorAll('.oai-summary-btn').forEach(btn => btn.innerHTML = '✨Summarize');/" ./extensions/xExtension-ArticleSummary/static/script.js
RUN cat <<'EOF' | tee ./extensions/xExtension-ArticleSummary/extension.php >/dev/null
<?php
class ArticleSummaryExtension extends Minz_Extension
{
  protected array $csp_policies = [
    'default-src' => '*',
  ];
  public function init()
  {
    $this->registerHook('entry_before_display', array($this, 'addSummaryButtons'));
    $this->registerController('ArticleSummary');
    Minz_View::appendStyle($this->getFileUrl('style.css', 'css'));
    Minz_View::appendScript($this->getFileUrl('axios.js', 'js'));
    Minz_View::appendScript($this->getFileUrl('marked.js', 'js'));
    Minz_View::appendScript($this->getFileUrl('script.js', 'js'));
  }
  public function addSummaryButtons($entry)
  {
    $url_summary = Minz_Url::display(array(
      'c' => 'ArticleSummary',
      'a' => 'summarize',
      'params' => array(
        'id' => $entry->id()
      )
    ));
    
    // Create top button and content div
    $topButton = '<div class="oai-summary-wrap">'
      . '<button data-request="' . $url_summary . '" class="oai-summary-btn"></button>'
      . '<div class="oai-summary-content"></div>'
      . '</div>';
    
    // Create spacer and bottom button
    $bottomButton = '<div>&nbsp;</div>'
      . '<div class="oai-summary-wrap">'
      . '<button data-request="' . $url_summary . '" class="oai-summary-btn"></button>'
      . '<div class="oai-summary-content"></div>'
      . '</div>';
    
    // Add both buttons to the content
    $entry->_content(
      $topButton
      . $entry->content()
      . $bottomButton
    );
    
    return $entry;
  }
  public function handleConfigureAction()
  {
    if (Minz_Request::isPost()) {
      FreshRSS_Context::$user_conf->oai_url = Minz_Request::param('oai_url', '');
      FreshRSS_Context::$user_conf->oai_key = Minz_Request::param('oai_key', '');
      FreshRSS_Context::$user_conf->oai_model = Minz_Request::param('oai_model', '');
      FreshRSS_Context::$user_conf->oai_prompt = Minz_Request::param('oai_prompt', '');
      FreshRSS_Context::$user_conf->oai_provider = Minz_Request::param('oai_provider', '');
      FreshRSS_Context::$user_conf->save();
    }
  }
}
EOF

# MarkPreviousAsRead extension
RUN git clone https://github.com/kalvn/freshrss-mark-previous-as-read.git && \
    cp -r freshrss-mark-previous-as-read/xExtension-MarkPreviousAsRead ./extensions && \
    rm -rf freshrss-mark-previous-as-read

# ReadingTime extension
RUN git clone https://framagit.org/Lapineige/FreshRSS_Extension-ReadingTime.git && \
    cp -r FreshRSS_Extension-ReadingTime ./extensions && \
    rm -rf FreshRSS_Extension-ReadingTime
RUN cat <<'EOF' | tee ./extensions/FreshRSS_Extension-ReadingTime/static/readingtime.js >/dev/null
(function reading_time() {
    'use strict';

    const reading_time = {
        flux_list: null,
        flux: null,
        textContent: null,
        words_count: null,
        read_time: null,
        reading_time: null,

        // Define a threshold for "long" reading time (in minutes)
        LONG_READING_TIME_THRESHOLD: 5, // Adjust this value as needed

        init: function () {
            const flux_list = document.querySelectorAll('[id^="flux_"]');

            for (let i = 0; i < flux_list.length; i++) {
                if ('readingTime' in flux_list[i].dataset) {
                    continue;
                }

                reading_time.flux = flux_list[i];

                // Count words or characters (for Chinese) or mixed text
                reading_time.words_count = reading_time.flux_words_count(flux_list[i]); // count the words or characters
                // change this number (in words/characters) to your preferred reading speed:
                reading_time.reading_time = reading_time.calc_read_time(reading_time.words_count, 300);

                flux_list[i].dataset.readingTime = reading_time.reading_time;

                const li = document.createElement('li');
                li.setAttribute('class', 'item date');
                li.style.width = '40px';
                li.style.overflow = 'hidden';
                li.style.textAlign = 'right';
                li.style.display = 'table-cell';

                // Set the text content
                li.textContent = reading_time.reading_time + '\u2009m';

                // Highlight long reading times
                if (reading_time.reading_time !== '<1' && reading_time.reading_time > reading_time.LONG_READING_TIME_THRESHOLD) {
                    li.style.color = 'red'; // Change text color to red
                    li.style.fontWeight = 'bold'; // Make text bold
                    // li.textContent += ' ⏳'; // Add an icon or indicator
                }

                const ul = document.querySelector('#' + reading_time.flux.id + ' ul.horizontal-list');
                ul.insertBefore(li, ul.children[ul.children.length - 1]);
                if (reading_time.reading_time !== '<1' && reading_time.reading_time > reading_time.LONG_READING_TIME_THRESHOLD) {
                    // ul.children[3].children[0].style.color='red';  // change title color
                    ul.children[3].children[0].text='⏳'+ul.children[3].children[0].text
                }
            }
        },

        flux_words_count: function flux_words_count(flux) {
            // Get textContent from the article itself (not the header, not the bottom line):
            reading_time.textContent = flux.querySelector('.flux_content .content').textContent;

            // Remove extra spaces and newlines (optional, for non-Chinese text)
            reading_time.textContent = reading_time.textContent.replace(/(^\s*)|(\s*$)/gi, ''); // exclude start and end white-space
            reading_time.textContent = reading_time.textContent.replace(/[ ]{2,}/gi, ' '); // 2 or more spaces to 1
            reading_time.textContent = reading_time.textContent.replace(/\n /, '\n'); // exclude newline with a start spacing

            // Count mixed Chinese characters and English words
            let wordCount = 0;
            const text = reading_time.textContent;

            // Split the text into an array of tokens (Chinese characters and English words)
            const tokens = text.split(/(\s+)/).filter(token => token.trim().length > 0);

            for (const token of tokens) {
                if (/[\u4e00-\u9fa5]/.test(token)) {
                    // If the token contains Chinese characters, count each character as a word
                    wordCount += token.length;
                } else {
                    // If the token is English (or other non-Chinese text), count it as one word
                    wordCount += 1;
                }
            }

            return wordCount;
        },

        calc_read_time: function calc_read_time(wd_count, speed) {
            reading_time.read_time = Math.round(wd_count / speed);

            if (reading_time.read_time === 0) {
                reading_time.read_time = '<1';
            }

            return reading_time.read_time;
        },
    };

    function add_load_more_listener() {
        reading_time.init();
        document.body.addEventListener('freshrss:load-more', function (e) {
            reading_time.init();
        });
    }

    if (document.readyState && document.readyState !== 'loading') {
        add_load_more_listener();
    } else if (document.addEventListener) {
        document.addEventListener('DOMContentLoaded', add_load_more_listener, false);
    }
}());
EOF

# Patch freshrss files
# https://github.com/FreshRSS/FreshRSS/blob/edge/p/scripts/main.js
# line 1299
# COPY ./main.js  ./p/scripts/main.js

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
