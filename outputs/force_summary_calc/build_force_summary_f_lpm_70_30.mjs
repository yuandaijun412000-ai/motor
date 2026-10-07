import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { SpreadsheetFile, Workbook } from "@oai/artifact-tool";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const rootDir = path.resolve(__dirname, "..", "..");
const inputPath = path.join(rootDir, "F_LPM_STATOR_LPM.csv");
const outputDir = __dirname;
const outputPath = path.join(outputDir, "F_LPM_STATOR_LPM_force_summary_70_30.xlsx");

const csvText = await fs.readFile(inputPath, "utf8");
const workbook = await Workbook.fromCSV(csvText, { sheetName: "原始数据" });
const rawSheet = workbook.worksheets.getItem("原始数据");
const resultSheet = workbook.worksheets.add("计算结果");
const weightSheet = workbook.worksheets.add("权重");

const rawValues = rawSheet.getUsedRange().values;
const headers = rawValues[0];
const rows = rawValues.slice(1).map((row) => [
  Number(row[0]),
  Number(row[1]),
  Number(row[2]),
  Number(row[3]),
]);

rawSheet.getRangeByIndexes(0, 0, rawValues.length, headers.length).values = [headers, ...rows];

const byPair = new Map();
for (const [lpm, statorLpm, a, force] of rows) {
  const key = `${lpm}|${statorLpm}`;
  if (!byPair.has(key)) {
    byPair.set(key, { lpm, statorLpm, forces: new Map() });
  }
  byPair.get(key).forces.set(a, force);
}

const combos = [...byPair.values()]
  .filter((item) => item.forces.has(0) && item.forces.has(-10))
  .sort((left, right) => left.lpm - right.lpm || left.statorLpm - right.statorLpm);

const missing = [...byPair.values()].filter((item) => !item.forces.has(0) || !item.forces.has(-10));
if (missing.length > 0) {
  throw new Error(`Missing paired a=0 or a=-10 data for ${missing.length} lpm/stator_lpm combinations.`);
}

weightSheet.getRange("A1:B3").values = [
  ["位移工况", "权重"],
  ["a=0 mm", 0.7],
  ["a=-10 mm", 0.3],
];
weightSheet.getRange("A1:B1").format = {
  fill: "#1F4E78",
  font: { bold: true, color: "#FFFFFF" },
};
weightSheet.getRange("B2:B3").format.numberFormat = "0%";
weightSheet.getRange("A1:B3").format.borders = { preset: "all", style: "thin", color: "#D9E2F3" };
weightSheet.getRange("A:A").format.columnWidth = 16;
weightSheet.getRange("B:B").format.columnWidth = 10;
weightSheet.showGridLines = false;

const resultHeaders = [
  "lpm [mm]",
  "stator_lpm [mm]",
  "推力波动 |F(a=0)-F(a=-10)| [N]",
  "加权平均推力 70%*F(a=0)+30%*F(a=-10) [N]",
];
const dataRows = combos.map(({ lpm, statorLpm }) => [lpm, statorLpm, null, null]);
resultSheet.getRangeByIndexes(0, 0, dataRows.length + 1, resultHeaders.length).values = [
  resultHeaders,
  ...dataRows,
];

const rawLastRow = rows.length + 1;
const forceFor = (rowIndex, aValue) =>
  `SUMIFS('原始数据'!$D$2:$D$${rawLastRow},'原始数据'!$A$2:$A$${rawLastRow},A${rowIndex},'原始数据'!$B$2:$B$${rawLastRow},B${rowIndex},'原始数据'!$C$2:$C$${rawLastRow},${aValue})`;

const formulas = combos.map((_, index) => {
  const rowIndex = index + 2;
  const forceA0 = forceFor(rowIndex, 0);
  const forceAMinus10 = forceFor(rowIndex, -10);
  return [
    `=ABS(${forceA0}-${forceAMinus10})`,
    `='权重'!$B$2*${forceA0}+'权重'!$B$3*${forceAMinus10}`,
  ];
});

resultSheet.getRangeByIndexes(1, 2, formulas.length, 2).formulas = formulas;

const resultLastRow = dataRows.length + 1;
resultSheet.getRange("A1:D1").format = {
  fill: "#1F4E78",
  font: { bold: true, color: "#FFFFFF" },
  wrapText: true,
};
resultSheet.getRange(`A2:B${resultLastRow}`).format.numberFormat = "0";
resultSheet.getRange(`C2:D${resultLastRow}`).format.numberFormat = "0.000";
resultSheet.getRange(`A1:D${resultLastRow}`).format.borders = { preset: "all", style: "thin", color: "#D9E2F3" };
resultSheet.getRange("A:A").format.columnWidth = 12;
resultSheet.getRange("B:B").format.columnWidth = 16;
resultSheet.getRange("C:C").format.columnWidth = 30;
resultSheet.getRange("D:D").format.columnWidth = 42;
resultSheet.getRange("A:D").format.verticalAlignment = "center";
resultSheet.getRange(`A2:D${resultLastRow}`).format.horizontalAlignment = "right";
resultSheet.freezePanes.freezeRows(1);
resultSheet.showGridLines = false;
const resultTable = resultSheet.tables.add(`A1:D${resultLastRow}`, true, "ForceSummaryTable");
resultTable.showFilterButton = true;

rawSheet.getRange("A1:D1").format = {
  fill: "#5B9BD5",
  font: { bold: true, color: "#FFFFFF" },
};
rawSheet.getRange("A:C").format.columnWidth = 18;
rawSheet.getRange("D:D").format.columnWidth = 32;
rawSheet.getRange(`A2:C${rawLastRow}`).format.numberFormat = "0";
rawSheet.getRange(`D2:D${rawLastRow}`).format.numberFormat = "0.000000";
rawSheet.freezePanes.freezeRows(1);
rawSheet.showGridLines = false;

const summaryInspect = await workbook.inspect({
  kind: "table",
  sheetId: "计算结果",
  range: "A1:D10",
  include: "values,formulas",
  tableMaxRows: 10,
  tableMaxCols: 4,
  maxChars: 5000,
});
console.log(summaryInspect.ndjson);

const errors = await workbook.inspect({
  kind: "match",
  searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A",
  options: { useRegex: true, maxResults: 300 },
  summary: "final formula error scan",
  maxChars: 3000,
});
console.log(errors.ndjson);

for (const [sheetName, range] of [
  ["计算结果", "A1:D25"],
  ["权重", "A1:B3"],
  ["原始数据", "A1:D25"],
]) {
  const preview = await workbook.render({
    sheetName,
    range,
    scale: 2,
    format: "png",
  });
  await fs.writeFile(
    path.join(outputDir, `F_LPM_STATOR_LPM_${sheetName}_70_30.png`),
    new Uint8Array(await preview.arrayBuffer()),
  );
}

await fs.mkdir(outputDir, { recursive: true });
const xlsx = await SpreadsheetFile.exportXlsx(workbook);
await xlsx.save(outputPath);

console.log(
  JSON.stringify({
    outputPath,
    inputRows: rows.length,
    outputRows: combos.length,
    columns: resultHeaders,
  }),
);
