---
title: Logging
---

# Logging

The SDK has built in support for structured logging via the [katip](https://hackage.haskell.org/package/katip) logging library. Even still, the SDK is agnostic to where you want your logs to go. Katip logs are managed by *scribes* whose job is precisely this, so the output depends on which scribes you use. The two most common scribes are the [console scribe](https://hackage.haskell.org/package/katip-0.8.3.0/docs/Katip-Scribes-Handle.html#v:mkHandleScribe) and the [Elasticsearch scribe](https://hackage.haskell.org/package/katip-elasticsearch).

The `Nameservice` application has support for either scribe -- it will use Elasticsearch if you provide the `ES_HOST` and `ES_PORT` environment variables or otherwise will default to console logging. The docker deployment is configured to use Elasticsearch.

## Logging to Elasticsearch

The docker network includes an `elk` image (Elasticsearch, Logstash, Kibana) for persisting and querying logs. You can read more about this stack [here](https://www.elastic.co/what-is/elk-stack). In summary `elk` is a powerful solution for hosting searchable structured logs.

When logging to Elasticsearch, you can use the Kibana dashboard for creating queries and visualizations. We will cover the basics here. If you have already launched the [docker network](TODO: Where is the instructions for this?), you can view the Kibana dashboard by going to http://localhost:5601/app/kibana. You should see something like

<img src="https://raw.githubusercontent.com/f-o-a-m/kepler/master/hs-abci-docs/nameservice/images/kibana_welcome_screen.png" width="50%"/>

To create an index (a searchable pattern), click on the *Management* tab, click *Create Index*, and enter `nameservice` as the pattern. You should see something like this:

<img src="https://raw.githubusercontent.com/f-o-a-m/kepler/master/hs-abci-docs/nameservice/images/kibana_management.png" width="50%"/>

You can ignore the advanced options, e.g. time filter, for now:

<img src="https://raw.githubusercontent.com/f-o-a-m/kepler/master/hs-abci-docs/nameservice/images/kibana_management_2.png" width="50%"/>

To view and search the logs, you can click the `Discover` tab. You should see all of the logs in the resulting search, from both server and application:

<img src="https://raw.githubusercontent.com/f-o-a-m/kepler/master/hs-abci-docs/nameservice/images/kibana_discover.png" width="50%"/>

## Searching a Log Index

### Log Structure

The log structure is effectively a JSON object (with nesting). There are a few fields that are worth pointing out:

- `message_type`: the abci message type for the message that caused the logs, e.g. `beginBlock`, `deliverTx`, etc.
- `message_hash`: the SHA256 of the protobuf encoded bytes for the abci message that caused the logs.
- `ns` (namespace): a list of increasingly specific scopes for where the log originated. In this case, `nameservice` is the root namespace, `server` or `application` is the next scope.

Remember that the basic lifecycle of an `ABCI` message is that it first comes to the ABCI-server from tendermint, is then handed off to your application for processing, and finally the response is sent from the ABCI-server back to tendermint. In order to better track this lifecycle, we highly recommend you use the [logging middleware](https://github.com/f-o-a-m/kepler/blob/master/hs-abci-extra/src/Network/ABCI/Server/Middleware/Logger.hs). This middleware will attach the `message_type` and `message_hash` to the context for every single log that is produced, meaning that you can get a  trace for a given message by simply searching its hash.

### Querying the Logs

You can create custom search filters in the *Discover* tab, just click the *Add a filter* button near the search bar. For example, we can filter all of the logs for those that correspond to a *deliverTx* message:

<img src="https://raw.githubusercontent.com/f-o-a-m/kepler/master/hs-abci-docs/nameservice/images/kibana_discover_filter.png" width="50%"/>

(**NOTE**: If you run the e2e tests against the docker network, you should see search results corresponding to the transactions created by the test suite. )

Similarly, you can compose multiple filters to obtain only those logs emitted by the application itself during a *deliverTx* context, i.e. by filtering for `application` on the `ns` namespace field:

<img src="https://raw.githubusercontent.com/f-o-a-m/kepler/master/hs-abci-docs/nameservice/images/kibana_discover_filter_advanced.png" width="50%"/>

### Indexing Transaction Events

If you view the results from the filter `message_type=deliverTx, ns=application`, you might see results from the e2e test suite like

```json
...
  "data": {
      "message_type": "deliverTx",
      "event": {
        "old_value": "hello world",
        "name": "satoshi",
        "new_value": "goodbye to a world"
      },
      "event_type": "NameRemapped",
      "message_hash": "e9190e5b24e066eb3b967fb39ba9e8ec250393d5c61400b3ed2a9528d967d5e1"
    },
  "msg": "NameRemapped",
...
```

This log corresponds to an event emitted by the `Nameservice` module during transaction execution, namely the `NameRemapped` event that happens when the owner of a name changes the corresponding value. This is because of the following `BaseApp.logEvent` statement in the `setName` handler:

```haskell
  let event = NameRemapped
        { nameRemappedName = setNameName
        , nameRemappedNewValue = setNameValue
        , nameRemappedOldValue = whoisValue
        }
  BaseApp.emit event
  BaseApp.logEvent event
```

In this way the log index serves as a rudimentary event indexer for transaction events as well.
