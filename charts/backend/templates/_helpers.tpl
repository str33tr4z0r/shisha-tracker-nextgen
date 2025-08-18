{{- define "shisha-backend.name" -}}
shisha-backend
{{- end -}}

{{- define "shisha-backend.fullname" -}}
{{- printf "%s-%s" .Release.Name (include "shisha-backend.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "shisha-backend.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version -}}
{{- end -}}

{{- define "shisha-backend.labels" -}}
app.kubernetes.io/name: {{ include "shisha-backend.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "shisha-backend.selectorLabels" -}}
app: {{ include "shisha-backend.name" . }}
{{- end -}}