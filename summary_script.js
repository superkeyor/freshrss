const MAX_RETRIES = 3;
const INITIAL_RETRY_DELAY = 1000; // Start with 1 second

// Helper function for delay
function delay(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

// New retry helper function with exponential backoff
async function retryWithBackoff(fn, retries = MAX_RETRIES) {
  for (let i = 0; i < retries; i++) {
    try {
      return await fn();
    } catch (error) {
      if (i === retries - 1) throw error;
      
      const delay = INITIAL_RETRY_DELAY * Math.pow(2, i);
      console.log(`Attempt ${i + 1} failed, retrying in ${delay}ms...`);
      await new Promise(resolve => setTimeout(resolve, delay));
    }
  }
}

if (document.readyState && document.readyState !== 'loading') {
  configureSummarizeButtons();
} else {
  document.addEventListener('DOMContentLoaded', configureSummarizeButtons, false);
}

function configureSummarizeButtons() {
  document.getElementById('global').addEventListener('click', function (e) {
    for (var target = e.target; target && target != this; target = target.parentNode) {
      
      if (target.matches('.flux_header')) {
        target.nextElementSibling.querySelectorAll('.oai-summary-btn').forEach(btn => btn.innerHTML = '✨Summarize');
      }

      if (target.matches('.oai-summary-btn')) {
        e.preventDefault();
        e.stopPropagation();
        if (target.dataset.request) {
          summarizeButtonClick(target);
        }
        break;
      }
    }
  }, false);
}

function setOaiState(container, statusType, statusMsg, summaryText) {
  const button = container.querySelector('.oai-summary-btn');
  const content = container.querySelector('.oai-summary-content');
  // 根据 state 设置不同的状态
  if (statusType === 1) {
    container.classList.add('oai-loading');
    container.classList.remove('oai-error');
    content.innerHTML = statusMsg;
    button.disabled = true;
  } else if (statusType === 2) {
    container.classList.remove('oai-loading');
    container.classList.add('oai-error');
    content.innerHTML = statusMsg;
    button.disabled = false;
  } else {
    container.classList.remove('oai-loading');
    container.classList.remove('oai-error');
    if (statusMsg === 'finish'){
      button.disabled = false;
    }
  }

  console.log(content);
  
  if (summaryText) {
    content.innerHTML = summaryText.replace(/(?:\r\n|\r|\n)/g, '<br>');
  }
}

// Modify summarizeButtonClick function
async function summarizeButtonClick(target) {
  const container = target.parentNode;
  if (container.classList.contains('oai-loading')) return;

  setOaiState(container, 1, '加载中', null);

  try {
    const response = await retryWithBackoff(async () => {
      const response = await axios.post(target.dataset.request, {
        ajax: true,
        _csrf: context.csrf
      }, {
        headers: { 'Content-Type': 'application/json' }
      });

      if (!response.data?.response?.data) {
        throw new Error('Invalid response structure');
      }

      return response;
    });

    const xresp = response.data;

    if (xresp.response.error) {
      setOaiState(container, 2, xresp.response.data, null);
      return;
    }

    const oaiParams = xresp.response.data;
    const oaiProvider = xresp.response.provider;
    
    if (oaiProvider === 'openai') {
      await sendOpenAIRequest(container, oaiParams);
    } else {
      await sendOllamaRequest(container, oaiParams);
    }
  } catch (error) {
    console.error('Final error after retries:', error);
    const errorMessage = error.response?.data?.message || error.message || '请求失败 / Request Failed';
    setOaiState(container, 2, errorMessage, null);
  }
}

// Modify sendOpenAIRequest function
async function sendOpenAIRequest(container, oaiParams) {
  const makeRequest = async () => {
    const body = { ...oaiParams };
    delete body.oai_url;
    delete body.oai_key;

    const response = await fetch(oaiParams.oai_url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${oaiParams.oai_key}`
      },
      body: JSON.stringify(body)
    });

    if (!response.ok) {
      throw new Error(`API request failed with status ${response.status}`);
    }

    return response;
  };

  try {
    const response = await retryWithBackoff(makeRequest);
    const reader = response.body.getReader();
    const decoder = new TextDecoder('utf-8');

    while (true) {
      const { done, value } = await reader.read();
      if (done) {
        setOaiState(container, 0, 'finish', null);
        break;
      }

      const chunk = decoder.decode(value, { stream: true });
      const text = JSON.parse(chunk)?.choices[0]?.message?.content || '';
      setOaiState(container, 0, null, marked.parse(text));
    }
  } catch (error) {
    console.error('OpenAI request failed:', error);
    setOaiState(container, 2, error.message || '请求失败 / Request Failed', null);
  }
}

async function sendOllamaRequest(container, oaiParams, retryCount = 0){
  try {
    const response = await fetch(oaiParams.oai_url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${oaiParams.oai_key}`
      },
      body: JSON.stringify(oaiParams)
    });

    if (!response.ok) {
      if (retryCount < MAX_RETRIES) {
        setOaiState(container, 1, `重试中... (${retryCount + 1}/${MAX_RETRIES})`, null);
        await delay(RETRY_DELAY);
        return sendOllamaRequest(container, oaiParams, retryCount + 1);
      }
      throw new Error('请求失败 / Request Failed');
    }
  
    const reader = response.body.getReader();
    const decoder = new TextDecoder('utf-8');
    let text = '';
    let buffer = '';

    while (true) {
      const { done, value } = await reader.read();
      if (done) {
        setOaiState(container, 0, 'finish', null);
        break;
      }
      buffer += decoder.decode(value, { stream: true });
      // Try to process complete JSON objects from the buffer
      let endIndex;
      while ((endIndex = buffer.indexOf('\n')) !== -1) {
        const jsonString = buffer.slice(0, endIndex).trim();
        try {
          if (jsonString) {
            const json = JSON.parse(jsonString);
            text += json.response
            setOaiState(container, 0, null, marked.parse(text));
          }
        } catch (e) {
          // If JSON parsing fails, output the error and keep the chunk for future attempts
          console.error('Error parsing JSON:', e, 'Chunk:', jsonString);
        }
        // Remove the processed part from the buffer
        buffer = buffer.slice(endIndex + 1); // +1 to remove the newline character
      }
    }
  } catch (error) {
    if (retryCount < MAX_RETRIES) {
      setOaiState(container, 1, `重试中... (${retryCount + 1}/${MAX_RETRIES})`, null);
      await delay(RETRY_DELAY);
      return sendOllamaRequest(container, oaiParams, retryCount + 1);
    }
    console.error(error);
    setOaiState(container, 2, '请求失败 / Request Failed', null);
  }
}

