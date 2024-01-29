import software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.model.S3Exception;
import software.amazon.awssdk.core.sync.RequestBody;

import org.apache.http.client.methods.HttpGet;
import org.apache.http.impl.client.CloseableHttpClient;
import org.apache.http.impl.client.HttpClients;
import org.apache.http.util.EntityUtils;
import org.apache.http.HttpResponse;

import com.fasterxml.jackson.databind.ObjectMapper;

import java.io.IOException;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;

public class OpenSkyToS3 {
    private static final String BUCKET_NAME = System.getenv("BUCKET_NAME");

    public static void main(String[] args) {
        try {
            String response = makeOpenSkyRequest();
            uploadToS3(response);
        } catch (IOException | S3Exception e) {
            e.printStackTrace();
        }
    }

    private static String makeOpenSkyRequest() throws IOException {
        String url = "https://opensky-network.org/api/states/all?lamin=49.00&lamax=54.83&lomin=14.12&lomax=24.15";
        CloseableHttpClient httpClient = HttpClients.createDefault();
        HttpGet request = new HttpGet(url);
        HttpResponse response = httpClient.execute(request);
        String responseBody = EntityUtils.toString(response.getEntity());
        httpClient.close();
        return responseBody;
    }

    private static void uploadToS3(String data) throws IOException {
        S3Client s3 = S3Client.builder()
                .region(Region.AWS_GLOBAL) // Set the appropriate region
                .credentialsProvider(DefaultCredentialsProvider.create())
                .build();

        String key = "flights-" + LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd-HH-mm-ss")) + ".json";
        PutObjectRequest putObjectRequest = PutObjectRequest.builder()
                .bucket(BUCKET_NAME)
                .key(key)
                .build();

        s3.putObject(putObjectRequest, RequestBody.fromString(data));
    }
}
