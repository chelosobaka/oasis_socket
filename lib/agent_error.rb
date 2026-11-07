# Отказ команды агента. Текст уходит в Rails второй строкой ответа (см. OasisTCPSocket),
# поэтому пишем его так, чтобы админ понял, что чинить на сервере.
class AgentError < StandardError; end
