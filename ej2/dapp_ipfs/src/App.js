import React, { useState } from "react";
import "./App.css";
import { create } from "kubo-rpc-client";
import { ethers } from "ethers"; // ethers v5.7.0
import { addresses, abis } from "./contracts";

// ---------------------------------------------------------------
// Conexion con Ethereum (MetaMask) e IPFS (nodo Kubo en Docker)
// ---------------------------------------------------------------
const IPFS_API = "/ip4/127.0.0.1/tcp/5001";
const provider = new ethers.providers.Web3Provider(window.ethereum);
const readOnly = new ethers.Contract(addresses.traceability, abis.traceability, provider);

async function getWriter() {
  await provider.send("eth_requestAccounts", []);
  return readOnly.connect(provider.getSigner());
}

async function uploadToIpfs(file) {
  const client = create(IPFS_API);
  const bytes = new Uint8Array(await file.arrayBuffer());
  const { cid } = await client.add(bytes);
  // Copia al MFS del nodo para verlo en la pestana "Files" del dashboard
  try {
    await client.files.cp(`/ipfs/${cid}`, `/${cid}`);
  } catch (e) {
    /* ya existia */
  }
  return cid.toString();
}

async function downloadFromIpfs(cid) {
  const client = create(IPFS_API);
  const chunks = [];
  for await (const chunk of client.cat(cid)) chunks.push(chunk);
  return new Blob(chunks);
}

// Recalcula el CID del contenido sin guardarlo, para comprobar su integridad
async function hashOf(blob) {
  const client = create(IPFS_API);
  const bytes = new Uint8Array(await blob.arrayBuffer());
  const { cid } = await client.add(bytes, { onlyHash: true });
  return cid.toString();
}

const fmtDate = (ts) => new Date(ts.toNumber() * 1000).toLocaleString();
const short = (a) => `${a.slice(0, 6)}...${a.slice(-4)}`;

async function nameOf(addr) {
  const n = await readOnly.operatorNames(addr);
  return n ? `${n} (${short(addr)})` : short(addr);
}

// Lee un lote con sus pasos, evidencias e ingredientes (recursivo)
async function loadBatch(id, seen = new Set()) {
  if (seen.has(id)) return null;
  seen.add(id);

  const b = await readOnly.batches(id);
  if (b.creator === ethers.constants.AddressZero) throw new Error(`El lote ${id} no existe`);

  const steps = [];
  const nSteps = (await readOnly.stepCount(id)).toNumber();
  for (let i = 0; i < nSteps; i++) {
    const s = await readOnly.getStep(id, i);
    steps.push({ who: await nameOf(s.operator), when: fmtDate(s.timestamp), location: s.location });
  }

  const evidences = [];
  const nEv = (await readOnly.evidenceCount(id)).toNumber();
  for (let i = 0; i < nEv; i++) {
    const e = await readOnly.getEvidence(id, i);
    evidences.push({ who: await nameOf(e.operator), when: fmtDate(e.timestamp), cid: e.cid, docType: e.docType });
  }

  const ingredients = [];
  for (const ingId of await readOnly.getIngredients(id)) {
    const sub = await loadBatch(ingId.toNumber(), seen);
    if (sub) ingredients.push(sub);
  }

  return {
    id,
    name: b.name,
    isProduct: b.isProduct,
    custodian: await nameOf(b.custodian),
    pending: b.pendingRecipient === ethers.constants.AddressZero ? null : short(b.pendingRecipient),
    steps,
    evidences,
    ingredients,
  };
}

// ---------------------------------------------------------------
// Estilos minimos
// ---------------------------------------------------------------
const S = {
  page: { maxWidth: 760, margin: "0 auto", padding: 24, fontFamily: "system-ui, sans-serif", color: "#222" },
  tabs: { display: "flex", gap: 8, margin: "16px 0", flexWrap: "wrap" },
  tab: (on) => ({
    padding: "8px 14px", border: "1px solid #888", borderRadius: 6, cursor: "pointer",
    background: on ? "#222" : "#fff", color: on ? "#fff" : "#222",
  }),
  field: { display: "block", width: "100%", padding: 8, margin: "6px 0 12px", boxSizing: "border-box" },
  btn: { padding: "8px 16px", cursor: "pointer", marginRight: 8 },
  msg: { padding: 10, margin: "16px 0", background: "#f1efe8", borderRadius: 6, wordBreak: "break-word" },
  node: { borderLeft: "2px solid #bbb", paddingLeft: 12, margin: "12px 0 12px 8px" },
  small: { fontSize: 13, color: "#555" },
};

function Field({ label, children }) {
  return (
    <label>
      {label}
      {children}
    </label>
  );
}

// ---------------------------------------------------------------
// Pantalla 1: alta de lote (con certificado opcional)
// ---------------------------------------------------------------
function CreateBatch({ run }) {
  const [name, setName] = useState("");
  const [location, setLocation] = useState("");
  const [ingredients, setIngredients] = useState("");
  const [file, setFile] = useState(null);

  const submit = (e) => {
    e.preventDefault();
    run(async (say) => {
      const c = await getWriter();
      const ids = ingredients.split(",").map((x) => x.trim()).filter(Boolean).map(Number);
      say("Confirma en MetaMask la creacion del lote...");
      const receipt = await (await c.createBatch(name, location, ids)).wait();
      const batchId = receipt.events.find((ev) => ev.event === "BatchCreated").args.batchId.toString();
      if (file) {
        say(`Lote ${batchId} creado. Subiendo certificado a IPFS...`);
        const cid = await uploadToIpfs(file);
        say("Confirma en MetaMask el registro del CID...");
        await (await c.attachEvidence(batchId, cid, "certificado")).wait();
        say(`Lote ${batchId} creado con certificado. CID: ${cid}`);
      } else {
        say(`Lote ${batchId} creado.`);
      }
    });
  };

  return (
    <form onSubmit={submit}>
      <Field label="Nombre del lote o producto">
        <input style={S.field} value={name} onChange={(e) => setName(e.target.value)} required />
      </Field>
      <Field label="Lugar de creacion">
        <input style={S.field} value={location} onChange={(e) => setLocation(e.target.value)} required />
      </Field>
      <Field label="IDs de ingredientes (separados por comas; vacio si es materia prima)">
        <input style={S.field} value={ingredients} onChange={(e) => setIngredients(e.target.value)} placeholder="1, 2" />
      </Field>
      <Field label="Certificado (opcional)">
        <input style={S.field} type="file" onChange={(e) => setFile(e.target.files[0])} />
      </Field>
      <button style={S.btn} type="submit">Crear lote</button>
    </form>
  );
}

// ---------------------------------------------------------------
// Pantalla 2: subir evidencia a un lote existente
// ---------------------------------------------------------------
const MAX_TEMP = 4; // umbral de la cadena de frio (grados C)

function AttachEvidence({ run }) {
  const [batchId, setBatchId] = useState("");
  const [docType, setDocType] = useState("certificado");
  const [file, setFile] = useState(null);

  const submit = (e) => {
    e.preventDefault();
    if (!file) return;
    run(async (say) => {
      let warning = "";
      if (docType === "temperatura") {
        // Flujo D: si alguna lectura supera el umbral, se avisa
        try {
          const data = JSON.parse(await file.text());
          const over = data.lecturas.filter((l) => l.temperaturaC > MAX_TEMP);
          if (over.length) warning = ` ATENCION: ${over.length} lecturas superan ${MAX_TEMP} C.`;
        } catch (err) {
          /* no es el JSON del sensor: se sube igualmente */
        }
      }
      const c = await getWriter();
      say("Subiendo archivo a IPFS...");
      const cid = await uploadToIpfs(file);
      say("Confirma en MetaMask el registro del CID...");
      await (await c.attachEvidence(batchId, cid, docType)).wait();
      say(`Evidencia registrada en el lote ${batchId}. CID: ${cid}.${warning}`);
    });
  };

  return (
    <form onSubmit={submit}>
      <Field label="ID del lote (debes ser su custodio)">
        <input style={S.field} type="number" min="1" value={batchId} onChange={(e) => setBatchId(e.target.value)} required />
      </Field>
      <Field label="Tipo de documento">
        <select style={S.field} value={docType} onChange={(e) => setDocType(e.target.value)}>
          <option value="certificado">Certificado</option>
          <option value="analisis">Analisis de laboratorio</option>
          <option value="temperatura">Registro de temperatura</option>
          <option value="inspeccion">Inspeccion</option>
        </select>
      </Field>
      <Field label="Archivo">
        <input style={S.field} type="file" onChange={(e) => setFile(e.target.files[0])} required />
      </Field>
      <button style={S.btn} type="submit">Subir a IPFS y registrar</button>
    </form>
  );
}

// ---------------------------------------------------------------
// Pantalla 3: transferencia de custodia
// ---------------------------------------------------------------
function Transfer({ run }) {
  const [batchId, setBatchId] = useState("");
  const [recipient, setRecipient] = useState("");
  const [location, setLocation] = useState("");

  return (
    <div>
      <Field label="ID del lote">
        <input style={S.field} type="number" min="1" value={batchId} onChange={(e) => setBatchId(e.target.value)} />
      </Field>

      <h3>Si eres el custodio actual</h3>
      <Field label="Direccion del receptor (debe ser operador autorizado)">
        <input style={S.field} value={recipient} onChange={(e) => setRecipient(e.target.value)} placeholder="0x..." />
      </Field>
      <button style={S.btn} onClick={() => run(async (say) => {
        const c = await getWriter();
        say("Confirma en MetaMask...");
        await (await c.proposeTransfer(batchId, recipient)).wait();
        say(`Transferencia del lote ${batchId} propuesta. El receptor debe aceptarla.`);
      })}>Proponer transferencia</button>
      <button style={S.btn} onClick={() => run(async (say) => {
        const c = await getWriter();
        say("Confirma en MetaMask...");
        await (await c.cancelTransfer(batchId)).wait();
        say("Propuesta cancelada.");
      })}>Cancelar propuesta</button>

      <h3>Si eres el receptor</h3>
      <Field label="Lugar de recepcion">
        <input style={S.field} value={location} onChange={(e) => setLocation(e.target.value)} />
      </Field>
      <button style={S.btn} onClick={() => run(async (say) => {
        const c = await getWriter();
        say("Confirma en MetaMask...");
        await (await c.acceptTransfer(batchId, location)).wait();
        say(`Custodia del lote ${batchId} aceptada.`);
      })}>Aceptar transferencia</button>
    </div>
  );
}

// ---------------------------------------------------------------
// Pantalla 4: consulta por batchId (vista del consumidor / auditor)
// ---------------------------------------------------------------
function BatchView({ b, checks, onVerify }) {
  return (
    <div style={S.node}>
      <strong>Lote {b.id}: {b.name}</strong> <span style={S.small}>({b.isProduct ? "producto elaborado" : "materia prima"})</span>
      <div style={S.small}>
        Custodio: {b.custodian}
        {b.pending && ` | Transferencia pendiente a ${b.pending}`}
      </div>

      <div><em>Recorrido</em></div>
      <ol style={S.small}>
        {b.steps.map((s, i) => (
          <li key={i}>{s.location} - {s.who} - {s.when}</li>
        ))}
      </ol>

      <div><em>Evidencias</em></div>
      {b.evidences.length === 0 && <div style={S.small}>Sin evidencias.</div>}
      <ul style={S.small}>
        {b.evidences.map((ev, i) => {
          const check = checks[ev.cid];
          return (
            <li key={i}>
              {ev.docType} - {ev.who} - {ev.when}<br />
              <code>{ev.cid}</code>{" "}
              <button onClick={() => onVerify(ev.cid)}>Descargar y verificar</button>{" "}
              {check && (check.ok
                ? <span style={{ color: "#0F6E56" }}>Integro. <a href={check.url} download={ev.cid}>Guardar archivo</a></span>
                : <span style={{ color: "#A32D2D" }}>{check.error || "NO coincide con el CID registrado"}</span>)}
            </li>
          );
        })}
      </ul>

      {b.ingredients.length > 0 && <div><em>Ingredientes</em></div>}
      {b.ingredients.map((ing) => (
        <BatchView key={ing.id} b={ing} checks={checks} onVerify={onVerify} />
      ))}
    </div>
  );
}

function Query({ run }) {
  const [batchId, setBatchId] = useState("");
  const [tree, setTree] = useState(null);
  const [checks, setChecks] = useState({});

  const search = (e) => {
    e.preventDefault();
    setTree(null);
    setChecks({});
    run(async (say) => {
      say("Leyendo la blockchain...");
      setTree(await loadBatch(Number(batchId)));
      say("");
    });
  };

  const verify = async (cid) => {
    try {
      const blob = await downloadFromIpfs(cid);
      const ok = (await hashOf(blob)) === cid;
      setChecks((c) => ({ ...c, [cid]: { ok, url: URL.createObjectURL(blob) } }));
    } catch (err) {
      setChecks((c) => ({ ...c, [cid]: { ok: false, error: "No se pudo descargar de IPFS: " + err.message } }));
    }
  };

  return (
    <div>
      <form onSubmit={search}>
        <Field label="ID del lote">
          <input style={S.field} type="number" min="1" value={batchId} onChange={(e) => setBatchId(e.target.value)} required />
        </Field>
        <button style={S.btn} type="submit">Consultar</button>
      </form>
      {tree && <BatchView b={tree} checks={checks} onVerify={verify} />}
    </div>
  );
}

// ---------------------------------------------------------------
// App
// ---------------------------------------------------------------
const TABS = [
  ["create", "Alta de lote", CreateBatch],
  ["evidence", "Subir evidencia", AttachEvidence],
  ["transfer", "Transferencia", Transfer],
  ["query", "Consulta", Query],
];

export default function App() {
  const [tab, setTab] = useState("create");
  const [msg, setMsg] = useState("");

  const run = async (fn) => {
    try {
      await fn(setMsg);
    } catch (err) {
      console.error(err);
      setMsg("Error: " + (err.reason || err.error?.message || err.message));
    }
  };

  const Current = TABS.find((t) => t[0] === tab)[2];

  return (
    <div style={S.page}>
      <h1>Trazabilidad alimentaria</h1>
      <div style={S.small}>Contrato: {addresses.traceability}</div>
      <div style={S.tabs}>
        {TABS.map(([id, label]) => (
          <button key={id} style={S.tab(tab === id)} onClick={() => { setTab(id); setMsg(""); }}>
            {label}
          </button>
        ))}
      </div>
      <Current run={run} />
      {msg && <div style={S.msg}>{msg}</div>}
    </div>
  );
}