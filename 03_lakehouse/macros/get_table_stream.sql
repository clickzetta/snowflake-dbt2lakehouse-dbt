{#
  ClickZetta replacement for Snowflake's get_stream() macro.

  Snowflake: SHOW STREAMS / CREATE STREAM ... SHOW_INITIAL_ROWS = TRUE
  ClickZetta: CREATE TABLE STREAM ... WITH PROPERTIES ('TABLE_STREAM_MODE' = 'ALL')

  Usage: {{ get_table_stream(ref('dim_customers')) }}
#}
{%- macro get_table_stream(table, stream_name=( (this.alias or this.name) ~ "_ts" )) -%}
    {%- set stream = api.Relation.create(
            database=this.database,
            schema=this.schema,
            identifier=stream_name) -%}

    {% if execute and flags.WHICH in ('run', 'build') %}
        {%- set stream_create_statement -%}
        create table stream if not exists {{ stream }}
        on table {{ table }}
        with properties ('TABLE_STREAM_MODE' = 'ALL')
        {%- endset -%}
        {%- do log("Ensuring table stream exists: " ~ stream, info=true) -%}
        {%- do run_query(stream_create_statement) -%}
    {%- endif -%}

    {{ return(stream) }}
{%- endmacro -%}
