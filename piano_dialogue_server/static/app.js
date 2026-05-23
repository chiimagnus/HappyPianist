// /generate panel
const genBtn = document.getElementById("genBtn");
const genStrategy = document.getElementById("genStrategy");
const genTopPGroup = document.getElementById("genTopPGroup");
const genTopP = document.getElementById("genTopP");
const genTopPValue = document.getElementById("genTopPValue");
const genMaxTokens = document.getElementById("genMaxTokens");
const genMaxTokensValue = document.getElementById("genMaxTokensValue");
const genNotes = document.getElementById("genNotes");
const genMessage = document.getElementById("genMessage");
const genResult = document.getElementById("genResult");

function showGenMessage(text, type) {
  genMessage.textContent = text;
  genMessage.className = `message show ${type}`;
}
function hideGenMessage() {
  genMessage.className = "message";
}

function updateGenUI() {
  const isModel = genStrategy.value === "model";
  genTopPGroup.style.display = isModel ? "block" : "none";
}
genStrategy.addEventListener("change", updateGenUI);
updateGenUI();

genTopP.addEventListener("input", () => {
  genTopPValue.textContent = genTopP.value;
});
genMaxTokens.addEventListener("input", () => {
  genMaxTokensValue.textContent = genMaxTokens.value;
});

genBtn.addEventListener("click", async () => {
  hideGenMessage();
  genResult.style.display = "none";

  let notesPayload;
  try {
    notesPayload = JSON.parse(genNotes.value);
    if (!Array.isArray(notesPayload)) {
      throw new Error("notes 必须是 JSON 数组");
    }
  } catch (err) {
    showGenMessage(`notes JSON 无效：${err.message}`, "error");
    return;
  }

  const payload = {
    type: "generate",
    protocol_version: 1,
    notes: notesPayload,
    params: {
      top_p: parseFloat(genTopP.value),
      max_tokens: parseInt(genMaxTokens.value, 10),
      strategy: genStrategy.value,
    },
  };

  genBtn.disabled = true;
  const originalText = genBtn.innerHTML;
  const isModel = genStrategy.value === "model";
  genBtn.innerHTML = `<div class="spinner"></div><span>${isModel ? "模型推理中（首次加载较慢）..." : "生成中..."}</span>`;

  try {
    const res = await fetch("/generate", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    const data = await res.json().catch(() => null);
    if (!res.ok) {
      const msg = data && data.message ? data.message : `HTTP ${res.status}`;
      throw new Error(msg);
    }

    genResult.textContent = JSON.stringify(data, null, 2);
    genResult.style.display = "block";
    showGenMessage(`成功：reply_notes=${(data.notes || []).length}`, "success");
  } catch (err) {
    showGenMessage(err.message || "请求失败", "error");
  } finally {
    genBtn.innerHTML = originalText;
    genBtn.disabled = false;
  }
});
