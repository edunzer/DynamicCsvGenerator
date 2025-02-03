public with sharing class DynamicCsvGenerator {

    public class CsvRequest {
        @InvocableVariable(required=true)
        public List<SObject> records;

        @InvocableVariable(required=true)
        public List<String> fieldNames;

        @InvocableVariable(required=true)
        public String fileName;

        @InvocableVariable(required=false)
        public String recordId; // Optional Record ID to relate file
    }

    public class CsvResponse {
        @InvocableVariable
        public String contentDocumentId;

        @InvocableVariable
        public String downloadUrl;
    }

    @InvocableMethod(label='Generate CSV File' description='Creates a CSV from records, stores it in Salesforce Files, and optionally relates it to a record.')
    public static List<CsvResponse> generateCsvFile(List<CsvRequest> requests) {
        List<CsvResponse> responses = new List<CsvResponse>();

        for (CsvRequest request : requests) {
            // 🚨 Validate Inputs
            if (request == null || request.records == null || request.records.isEmpty()) {
                throw new FlowException('Error: No records provided for CSV generation.');
            }
            if (request.fieldNames == null || request.fieldNames.isEmpty()) {
                throw new FlowException('Error: No field names provided.');
            }
            if (String.isBlank(request.fileName)) {
                throw new FlowException('Error: File name cannot be blank.');
            }

            // Ensure file has .csv extension
            String fileName = request.fileName.endsWith('.csv') ? request.fileName : request.fileName + '.csv';

            // Step 1: Create CSV Header
            String csvContent = String.join(request.fieldNames, ',') + '\n';

            // Step 2: Populate CSV Rows
            for (SObject record : request.records) {
                List<String> rowValues = new List<String>();

                for (String fieldName : request.fieldNames) {
                    String fieldValue = '';
                    try {
                        fieldValue = String.valueOf(record.get(fieldName) != null ? record.get(fieldName) : '');
                    } catch (Exception e) {
                        fieldValue = 'ERROR'; // Handle missing fields
                    }

                    // Escape CSV special characters
                    rowValues.add(fieldValue.escapeCsv());
                }

                csvContent += String.join(rowValues, ',') + '\n';
            }

            // Step 3: Create and Save as ContentVersion
            ContentVersion contentVersion = new ContentVersion();
            contentVersion.Title = fileName;
            contentVersion.PathOnClient = fileName;
            contentVersion.VersionData = Blob.valueOf(csvContent);
            contentVersion.IsMajorVersion = true;
            insert contentVersion;

            // Step 4: Retrieve ContentDocument ID
            ContentDocument contentDoc = [SELECT Id FROM ContentDocument WHERE Id IN 
                                          (SELECT ContentDocumentId FROM ContentVersion WHERE Id = :contentVersion.Id) 
                                          LIMIT 1];

            // Step 5: Optionally Relate ContentDocument to a Record
            if (String.isNotBlank(request.recordId)) {
                ContentDocumentLink contentDocLink = new ContentDocumentLink();
                contentDocLink.ContentDocumentId = contentDoc.Id;
                contentDocLink.LinkedEntityId = request.recordId;
                contentDocLink.ShareType = 'V'; // Viewer access
                insert contentDocLink;
            }

            // Step 6: Generate File Download Link
            String downloadUrl = '/sfc/servlet.shepherd/document/download/' + contentDoc.Id;

            // Step 7: Create Response
            CsvResponse response = new CsvResponse();
            response.contentDocumentId = contentDoc.Id;
            response.downloadUrl = downloadUrl;

            responses.add(response);
        }
        return responses;
    }
}
