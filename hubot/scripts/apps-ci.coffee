# Description:
#   Interact with your Jenkins CI server
#
# Dependencies:
#   None
#
# Configuration:
#   HUBOT_APPS_CI_URL
#   HUBOT_APPS_CI_AUTH
#
#   Auth should be in the "user:password" format.
#
# Commands:
#   hubot apps-ci b <jobNumber> - builds the job specified by jobNumber. List jobs to get number.
#   hubot apps-ci build <job> - builds the specified Jenkins job
#   hubot apps-ci build <job>, <params> - builds the specified Jenkins job with parameters as key=value&key2=value2
#   hubot apps-ci list <filter> - lists Jenkins jobs
#   hubot apps-ci describe <job> - Describes the specified Jenkins job

#
# Author:
#   dougcole

querystring = require 'querystring'

# Holds a list of jobs, so we can trigger them with a number
# instead of the job's name. Gets populated on when calling
# list.
jobList = []

jenkinsBuildById = (msg) ->
  # Switch the index with the job name
  job = jobList[parseInt(msg.match[1]) - 1]

  if job
    msg.match[1] = job
    jenkinsBuild(msg)
  else
    msg.reply "I couldn't find that job. Try `apps-ci list` to get a list."

jenkinsBuild = (msg, buildWithEmptyParameters) ->
    url = process.env.HUBOT_APPS_CI_URL
    job = querystring.escape msg.match[1]
    params = msg.match[3]
    command = if buildWithEmptyParameters then "buildWithParameters" else "build"
    path = if params then "#{url}/job/#{job}/buildWithParameters?#{params}" else "#{url}/job/#{job}/#{command}"

    req = msg.http(path)

    if process.env.HUBOT_APPS_CI_AUTH
      auth = new Buffer(process.env.HUBOT_APPS_CI_AUTH).toString('base64')
      req.headers Authorization: "Basic #{auth}"

    req.header('Content-Length', 0)
    req.post() (err, res, body) ->
        if err
          msg.reply "Jenkins says: #{err}"
        else if 200 <= res.statusCode < 400 # Or, not an error code.
          msg.reply "(#{res.statusCode}) Build started for #{job} #{url}/job/#{job}"
        else if 400 == res.statusCode
          jenkinsBuild(msg, true)
        else
          msg.reply "Jenkins says: Status #{res.statusCode} #{body}"

jenkinsDescribe = (msg) ->
    url = process.env.HUBOT_APPS_CI_URL
    job = msg.match[1]

    path = "#{url}/job/#{job}/api/json"

    req = msg.http(path)

    if process.env.HUBOT_APPS_CI_AUTH
      auth = new Buffer(process.env.HUBOT_APPS_CI_AUTH).toString('base64')
      req.headers Authorization: "Basic #{auth}"

    req.header('Content-Length', 0)
    req.get() (err, res, body) ->
        if err
          msg.send "Jenkins says: #{err}"
        else
          response = ""
          try
            content = JSON.parse(body)
            response += "JOB: #{content.displayName}\n"
            response += "URL: #{url}/job/#{job}\n"

            if content.description
              response += "DESCRIPTION: #{content.description}\n"

            response += "ENABLED: #{content.buildable}\n"
            response += "STATUS: #{content.color}\n"

            tmpReport = ""
            if content.healthReport.length > 0
              for report in content.healthReport
                tmpReport += "\n  #{report.description}"
            else
              tmpReport = " unknown"
            response += "HEALTH: #{tmpReport}\n"

            parameters = ""
            for item in content.actions
              if item.parameterDefinitions
                for param in item.parameterDefinitions
                  tmpDescription = if param.description then " - #{param.description} " else ""
                  tmpDefault = if param.defaultParameterValue then " (default=#{param.defaultParameterValue.value})" else ""
                  parameters += "\n  #{param.name}#{tmpDescription}#{tmpDefault}"

            if parameters != ""
              response += "PARAMETERS: #{parameters}\n"

            msg.send response

            if not content.lastBuild
              return

            path = "#{content.lastBuild.url}/api/json"
            req = msg.http(path)
            if process.env.HUBOT_APPS_CI_AUTH
              auth = new Buffer(process.env.HUBOT_APPS_CI_AUTH).toString('base64')
              req.headers Authorization: "Basic #{auth}"

            req.header('Content-Length', 0)
            req.get() (err, res, body) ->
                if err
                  msg.send "Jenkins says: #{err}"
                else
                  response = ""
                  try
                    content = JSON.parse(body)
                    console.log(JSON.stringify(content, null, 4))
                    jobstatus = content.result || 'PENDING'
                    jobdate = new Date(content.timestamp);
                    response += "LAST JOB: #{jobstatus}, #{jobdate}\n"

                    msg.send response
                  catch error
                    msg.send error

          catch error
            msg.send error

jenkinsList = (msg) ->
    url = process.env.HUBOT_APPS_CI_URL
    filter = new RegExp(msg.match[2], 'i')
    req = msg.http("#{url}/api/json")

    if process.env.HUBOT_APPS_CI_AUTH
      auth = new Buffer(process.env.HUBOT_APPS_CI_AUTH).toString('base64')
      req.headers Authorization: "Basic #{auth}"

    req.get() (err, res, body) ->
        response = ""
        if err
          msg.send "Jenkins says: #{err}"
        else
          try
            content = JSON.parse(body)
            for job in content.jobs
              # Add the job to the jobList
              index = jobList.indexOf(job.name)
              if index == -1
                jobList.push(job.name)
                index = jobList.indexOf(job.name)

              state = if job.color == "red" then "FAIL" else "PASS"
              if filter.test job.name
                response += "[#{index + 1}] #{state} #{job.name}\n"
            msg.send response
          catch error
            msg.send error

module.exports = (robot) ->
  robot.respond /apps-ci build ([\w\.\-_ ]+)(, (.+))?/i, (msg) ->
    jenkinsBuild(msg, false)

  robot.respond /apps-ci b (\d+)/i, (msg) ->
    jenkinsBuildById(msg)

  robot.respond /apps-ci list( (.+))?/i, (msg) ->
    jenkinsList(msg)

  robot.respond /apps-ci describe (.*)/i, (msg) ->
    jenkinsDescribe(msg)

  robot.jenkins = {
    list: jenkinsList,
    build: jenkinsBuild
  }