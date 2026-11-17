// Sensor de temperatura simulado para la cadena de frio.
// Uso:  node sensor.js [idLote]
// Genera lecturas_lote_<id>.json, que luego se sube desde la DApp
// (pestana "Subir evidencia", tipo "Registro de temperatura").

const fs = require("fs");

const batchId = process.argv[2] || "1";
const SAMPLES = 24;          // una lectura cada 15 min durante 6 horas
const BASE = 2.5;            // temperatura normal de la camara (grados C)
const MAX_TEMP = 4;          // umbral de seguridad

const start = Date.now() - SAMPLES * 15 * 60 * 1000;
const lecturas = [];

for (let i = 0; i < SAMPLES; i++) {
  let temp = BASE + (Math.random() - 0.5) * 1.5; // ruido normal
  // Simula un fallo de refrigeracion en el tramo central
  if (i >= 12 && i <= 15) temp += 2.5;
  lecturas.push({
    timestamp: new Date(start + i * 15 * 60 * 1000).toISOString(),
    temperaturaC: Number(temp.toFixed(1)),
  });
}

const fueraDeRango = lecturas.filter((l) => l.temperaturaC > MAX_TEMP);
const out = {
  loteId: Number(batchId),
  sensor: "SIM-001",
  umbralC: MAX_TEMP,
  lecturas,
};

const file = `lecturas_lote_${batchId}.json`;
fs.writeFileSync(file, JSON.stringify(out, null, 2));

console.log(`Archivo generado: ${file}`);
console.log(`Lecturas: ${lecturas.length}`);
console.log(`Maxima: ${Math.max(...lecturas.map((l) => l.temperaturaC))} C`);
console.log(`Fuera de rango (> ${MAX_TEMP} C): ${fueraDeRango.length}`);
