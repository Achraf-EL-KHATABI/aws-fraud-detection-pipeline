{
  "Comment": "Fraud detection daily batch: run Glue ETL job, then start the curated Crawler.",
  "StartAt": "RunGlueJob",
  "States": {
    "RunGlueJob": {
      "Type": "Task",
      "Resource": "arn:aws:states:::glue:startJobRun.sync",
      "Parameters": {
        "JobName": "${glue_job_name}"
      },
      "Retry": [
        {
          "ErrorEquals": [
            "Glue.ConcurrentRunsExceededException",
            "States.TaskFailed"
          ],
          "IntervalSeconds": 30,
          "MaxAttempts": 2,
          "BackoffRate": 2.0
        }
      ],
      "Catch": [
        {
          "ErrorEquals": [
            "States.ALL"
          ],
          "Next": "JobFailed",
          "ResultPath": "$.error"
        }
      ],
      "Next": "StartCrawler"
    },

    "StartCrawler": {
      "Type": "Task",
      "Resource": "arn:aws:states:::aws-sdk:glue:startCrawler",
      "Parameters": {
        "Name": "${glue_crawler_name}"
      },
      "Retry": [
        {
          "ErrorEquals": [
            "Glue.CrawlerRunningException"
          ],
          "IntervalSeconds": 30,
          "MaxAttempts": 3,
          "BackoffRate": 2.0
        }
      ],
      "Catch": [
        {
          "ErrorEquals": [
            "States.ALL"
          ],
          "Next": "CrawlerFailed",
          "ResultPath": "$.error"
        }
      ],
      "Next": "Succeeded"
    },

    "Succeeded": {
      "Type": "Succeed"
    },

    "JobFailed": {
      "Type": "Fail",
      "Error": "GlueJobFailed",
      "Cause": "The Glue ETL job failed; see the captured error in the execution input."
    },

    "CrawlerFailed": {
      "Type": "Fail",
      "Error": "GlueCrawlerFailed",
      "Cause": "The Glue Crawler failed to start or run; see the captured error in the execution input."
    }
  }
}
