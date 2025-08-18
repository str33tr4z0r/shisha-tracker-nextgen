{{- define "shisha-frontend.name" -}}
shisha-frontend
{{- end -}}

{{- define "shisha-frontend.fullname" -}}
{{- printf "%s-%s" .Release.Name (include "shisha-frontend.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "shisha-frontend.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version -}}
{{- end -}}

{{- define "shisha-frontend.labels" -}}
app.kubernetes.io/name: {{ include "shisha-frontend.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "shisha-frontend.selectorLabels" -}}
app: {{ include "shisha-frontend.name" . }}
{{- end -}}