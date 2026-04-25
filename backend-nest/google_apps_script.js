/**
 * CONFIGURATION
 */
const PROJECT_ID = 'phongvu-opshub'; // Điền Project ID của Google Cloud
const DATASET_ID = 'phongvu_opshub_database'; // Dataset dành riêng cho User
const TABLE_ID = 'all_users'; // Tên bảng lưu toàn bộ User trên BigQuery
const SHEET_NAME = 'Users'; // Tên Tab chứa dữ liệu trong mỗi file Sheet

// DANH SÁCH CÁC SHEET ID CẦN ĐỒNG BỘ (Đại ca có thể thêm nhiều ID vào đây)
const SPREADSHEET_IDS = [
  'ĐIỀN_ID_SHEET_1_VÀO_ĐÂY', // Ví dụ: '1-abcdefghijklmnop'
  // 'ID_SHEET_2',
  // 'ID_SHEET_3'
];

/**
 * Hàm chính để đồng bộ đa Sheet
 */
function syncMultipleSheetsToBigQuery() {
  const allRows = [];

  SPREADSHEET_IDS.forEach((id) => {
    try {
      const ss = SpreadsheetApp.openById(id);
      const sheet = ss.getSheetByName(SHEET_NAME);
      if (!sheet) {
        Logger.log(
          'Không tìm thấy Tab "%s" trong Sheet ID: %s',
          SHEET_NAME,
          id,
        );
        return;
      }

      const data = sheet.getDataRange().getValues();
      if (data.length <= 1) return;

      // Lấy dữ liệu bỏ qua header
      const rows = data.slice(1);
      allRows.push(...rows);
      Logger.log('Đã lấy %s dòng từ Sheet: %s', rows.length, ss.getName());
    } catch (e) {
      Logger.log('Lỗi khi mở Sheet ID %s: %s', id, e.message);
    }
  });

  if (allRows.length === 0) {
    Logger.log('Không có dữ liệu để đồng bộ.');
    return;
  }

  // Chuẩn bị payload dạng CSV
  const csvData = allRows
    .map((row) => {
      return row
        .map((cell) => {
          let cellStr = cell.toString().replace(/"/g, '""');
          return `"${cellStr}"`;
        })
        .join(',');
    })
    .join('\n');

  const blob = Utilities.newBlob(csvData, 'application/octet-stream');

  const job = {
    configuration: {
      load: {
        destinationTable: {
          projectId: PROJECT_ID,
          datasetId: DATASET_ID,
          tableId: TABLE_ID,
        },
        sourceFormat: 'CSV',
        writeDisposition: 'WRITE_TRUNCATE',
        autodetect: false,
        schema: {
          fields: [
            { name: 'email', type: 'STRING', mode: 'REQUIRED' },
            { name: 'first_name', type: 'STRING' },
            { name: 'last_name', type: 'STRING' },
            { name: 'role', type: 'STRING' },
            { name: 'branch_id', type: 'STRING' },
            { name: 'branch_name', type: 'STRING' },
            { name: 'status', type: 'STRING' },
          ],
        },
      },
    },
  };

  try {
    const result = BigQuery.Jobs.insert(job, PROJECT_ID, blob);
    Logger.log(
      'Đã đẩy lệnh Job gộp %s dòng thành công. Job ID: %s',
      allRows.length,
      result.jobReference.jobId,
    );
  } catch (err) {
    Logger.log('Lỗi khi đẩy lên BigQuery: %s', err.toString());
  }
}
