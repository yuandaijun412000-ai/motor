import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { SpreadsheetFile, Workbook } from "@oai/artifact-tool";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const rootDir = path.resolve(__dirname, "..", "..");
const inputPath = path.join(rootDir, "1S2P_L_F.csv");
const outputDir = __dirname;
const outputPath = path.join(outputDir, "1S2P_L_F_structure_summary.xlsx");

const csvText = await fs.readFile(inputPath, "utf8");
const workbook = await Workbook.fromCSV(csvText, { sheetName: "原始数据" });
const rawSheet = workbook.worksheets.getItem("原始数据");
const resultSheet = workbook.worksheets.add("计算结果");

const rawValues = rawSheet.getUsedRange().values;
const headers = rawValues[0];
const rows = rawValues.slice(1).map((row) => [
  Number(row[0]),
  Number(row[1]),
  Number(row[2]),
  Number(row[3]),
  Number(row[4]),
]);

rawSheet.getRangeByIndexes(0, 0, rawValues.length, headers.length).values = [headers, ...rows];

const structures = new Map();
for (const [lout, lpm, lpmspace] of rows) {
  const key = `${lout}|${lpm}|${lpmspace}`;
  if (!structures.has(key)) {
    structures.set(key, { lout, lpm, lpmspace });
  }
}

const sortedStructures = [...structures.values()].sort(
  (left, right) =>
    left.lout - right.lout ||
    left.lpm - right.lpm ||
    left.lpmspace - right.lpmspace,
);

const resultHeaders = [
  "lout [mm]",
  "lpm [mm]",
  "lpmspace [mm]",
  "平均推力 mean(F) [N]",
  "最大推力差值 max(F)-min(F) [N]",
];

const resultRows = sortedStructures.map(({ lout, lpm, lpmspace }) => [
  lout,
  lpm,
  lpmspace,
  null,
  null,
]);

resultSheet.getRangeByIndexes(0, 0, resultRows.length + 1, resultHeaders.length).values = [
  resultHeaders,
  ...resultRows,
];

const rawLastRow = rows.length + 1;
const criteria = (rowIndex) =>
  `'原始数据'!$A$2:$A$${rawLastRow},A${rowIndex},` +
  `'原始数据'!$B$2:$B$${rawLastRow},B${rowIndex},` +
  `'原始数据'!$C$2:$C$${rawLastRow},C${rowIndex}`;

const formulas = sortedStructures.map((_, index) => {
  const rowIndex = index + 2;
  const forceRange = `'原始数据'!$E$2:$E$${rawLastRow}`;
  return [
    `=AVERAGEIFS(${forceRange},${criteria(rowIndex)})`,
    `=MAXIFS(${forceRange},${criteria(rowIndex)})-MINIFS(${forceRange},${criteria(rowIndex)})`,
  ];
});

resultSheet.getRangeByIndexes(1, 3, formulas.length, 2).formulas = formulas;

const resultLastRow = resultRows.length + 1;
resultSheet.getRange("A1:E1").format = {
  fill: "#1F4E78",
  font: { bold: true, color: "#FFFFFF" },
  wrapText: true,
};
resultSheet.getRange(`A2:C${resultLastRow}`).format.numberFormat = "0";
resultSheet.getRange(`D2:E${resultLastRow}`).format.numberFormat = "0.000";
resultSheet.getRange(`A1:E${resultLastRow}`).format.borders = {
  preset: "all",
  style: "thin",
  color: "#D9E2F3",
};
resultSheet.getRange("A:A").format.columnWidth = 12;
resultSheet.getRange("B:B").format.columnWidth = 12;
resultSheet.getRange("C:C").format.columnWidth = 16;
resultSheet.getRange("D:D").format.columnWidth = 24;
resultSheet.getRange("E:E").format.columnWidth = 32;
resultSheet.getRange("A:E").format.verticalAlignment = "center";
resultSheet.getRange(`A2:E${resultLastRow}`).format.horizontalAlignment = "right";
resultSheet.freezePanes.freezeRows(1);
resultSheet.showGridLines = false;
const table = resultSheet.tables.add(`A1:E${resultLastRow}`, true, "StructureSummaryTable");
table.showFilterButton = true;

rawSheet.getRange("A1:E1").format = {
  fill: "#5B9BD5",
  font: { bold: true, color: "#FFFFFF" },
};
rawSheet.getRange("A:D").format.columnWidth = 16;
rawSheet.getRange("E:E").format.columnWidth = 30;
rawSheet.getRange(`A2:D${rawLastRow}`).format.numberFormat = "0";
rawSheet.getRange(`E2:E${rawLastRow}`).format.numberFormat = "0.000000";
rawSheet.freezePanes.freezeRows(1);
rawSheet.showGridLines = false;

const inspect = await workbook.inspect({
  kind: "table",
  sheetId: "计算结果",
  range: "A1:E10",
  include: "values,formulas",
  tableMaxRows: 10,
  tableMaxCols: 5,
  maxChars: 5000,
});
console.log(inspect.ndjson);

const errors = await workbook.inspect({
  kind: "match",
  searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A",
  options: { useRegex: true, maxResults: 300 },
  summary: "final formula error scan",
  maxChars: 3000,
});
console.log(errors.ndjson);

for (const [sheetName, range] of [
  ["计算结果", "A1:E25"],
  ["原始数据", "A1:E25"],
]) {
  const preview = await workbook.render({
    sheetName,
    range,
    scale: 2,
    format: "png",
  });
  await fs.writeFile(
    path.join(outputDir, `${sheetName}.png`),
    new Uint8Array(await preview.arrayBuffer()),
  );
}

const xlsx = await SpreadsheetFile.exportXlsx(workbook);
await xlsx.save(outputPath);

console.log(
  JSON.stringify({
    outputPath,
    inputRows: rows.length,
    outputRows: sortedStructures.length,
    columns: resultHeaders,
  }),
);
